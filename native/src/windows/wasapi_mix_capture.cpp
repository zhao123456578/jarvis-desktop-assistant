#ifdef _WIN32
#include "jarvis/windows.hpp"

#include <Windows.h>
#include <Audioclient.h>
#include <Mmdeviceapi.h>
#include <avrt.h>
#include <ksmedia.h>
#include <propidl.h>
#include <wrl/client.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

// 改造说明（AI Jarvis 本地补丁）：
// 原版只做默认播放设备的 WASAPI 回路采集（只听得见电脑在放什么）。
// 本版本保留系统声音，并把系统上"所有可用的录音设备"都打开混进同一路音频：
// 这台机器的 Windows 默认录音设备是一个没有信号的接口，只开默认设备等于没开麦克风，
// 全部打开可以避免这种坑。
//   JARVIS_MIC=0            关闭全部麦克风（恢复原版行为）
//   JARVIS_MIC_GAIN=2.0     调整麦克风增益（默认 1.8）
//   JARVIS_MIC_DEFAULT_ONLY=1  只用系统默认录音设备
namespace jarvis::win {
using Microsoft::WRL::ComPtr;
namespace {

void check(HRESULT hr, const char* what) { if (FAILED(hr)) throw std::runtime_error(what); }

bool env_flag(const char* name, bool fallback) {
  const char* value = std::getenv(name);
  if (!value) return fallback;
  std::string text(value);
  std::transform(text.begin(), text.end(), text.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return !(text == "0" || text == "false" || text == "off" || text == "no");
}

float mic_gain() {
  const char* value = std::getenv("JARVIS_MIC_GAIN");
  if (!value) return 1.0F;
  try {
    return std::clamp(std::stof(value), 0.0F, 8.0F);
  } catch (...) {
    return 1.0F;
  }
}

std::string to_utf8(const wchar_t* text) {
  if (!text) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
  if (size <= 1) return {};
  std::string out(static_cast<std::size_t>(size) - 1, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text, -1, out.data(), size, nullptr, nullptr);
  return out;
}

std::string device_friendly_name(IMMDevice* device) {
  ComPtr<IPropertyStore> store;
  if (FAILED(device->OpenPropertyStore(STGM_READ, &store)) || !store) return "(未知设备)";
  PROPERTYKEY key{};
  key.fmtid = GUID{0xa45c254e, 0xdf1c, 0x4efd, {0x80, 0x20, 0x67, 0xd1, 0x46, 0xa8, 0x50, 0xe0}};
  key.pid = 14;
  PROPVARIANT value;
  PropVariantInit(&value);
  std::string name = "(未知设备)";
  if (SUCCEEDED(store->GetValue(key, &value)) && value.vt == VT_LPWSTR) name = to_utf8(value.pwszVal);
  PropVariantClear(&value);
  return name;
}

// 把采集到的情况写进日志，方便排查（路径优先用 JARVIS_MIC_LOG）
void log_capture(const std::string& text) {
  const char* custom = std::getenv("JARVIS_MIC_LOG");
  std::string path = custom ? custom : "";
  if (path.empty()) {
    const char* local = std::getenv("LOCALAPPDATA");
    if (local) path = std::string(local) + "\\AIJarvis\\runtime\\mic-capture.log";
  }
  if (path.empty()) return;
  std::ofstream out(path, std::ios::app);
  if (out) out << text << std::endl;
}

struct Source {
  ComPtr<IMMDevice> device;
  ComPtr<IAudioClient> client;
  ComPtr<IAudioCaptureClient> capture;
  WAVEFORMATEX* mix{};
  std::uint32_t rate{};
  std::uint16_t channels{};
  std::string name{};

  Source() = default;
  Source(const Source&) = delete;
  Source& operator=(const Source&) = delete;
  ~Source() { close(); }

  void close() noexcept {
    if (client) client->Stop();
    capture.Reset();
    client.Reset();
    device.Reset();
    if (mix) { CoTaskMemFree(mix); mix = nullptr; }
  }

  [[nodiscard]] bool is_float() const noexcept {
    if (!mix) return false;
    if (mix->wFormatTag == WAVE_FORMAT_IEEE_FLOAT) return true;
    if (mix->wFormatTag != WAVE_FORMAT_EXTENSIBLE) return false;
    return reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(mix)->SubFormat == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
  }

  void open(IMMDevice* dev, DWORD stream_flags, const std::string& label) {
    device = dev;
    name = label;
    check(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                           reinterpret_cast<void**>(client.GetAddressOf())),
          "IAudioClient failed");
    check(client->GetMixFormat(&mix), "GetMixFormat failed");
    rate = mix->nSamplesPerSec;
    channels = mix->nChannels;
    check(client->Initialize(AUDCLNT_SHAREMODE_SHARED, stream_flags, 0, 0, mix, nullptr),
          "audio initialize failed");
    check(client->GetService(IID_PPV_ARGS(&capture)), "IAudioCaptureClient failed");
  }

  void start() { if (client) check(client->Start(), "audio start failed"); }

  [[nodiscard]] bool has_packets() {
    if (!capture) return false;
    UINT32 packets{};
    check(capture->GetNextPacketSize(&packets), "GetNextPacketSize failed");
    return packets > 0;
  }

  // 取走当前所有可读的包，压成单声道 float（采样率仍是这个设备自己的）
  std::vector<float> drain_mono() {
    std::vector<float> flat;
    if (!capture) return flat;
    UINT32 packets{};
    check(capture->GetNextPacketSize(&packets), "GetNextPacketSize failed");
    while (packets) {
      BYTE* data{}; UINT32 frames{}; DWORD flags{}; UINT64 device_position{}, qpc_position{};
      check(capture->GetBuffer(&data, &frames, &flags, &device_position, &qpc_position), "GetBuffer failed");
      const std::size_t samples = std::size_t(frames) * channels;
      const std::size_t base = flat.size();
      flat.resize(base + samples);
      if (flags & AUDCLNT_BUFFERFLAGS_SILENT) {
        std::fill(flat.begin() + static_cast<std::ptrdiff_t>(base), flat.end(), 0.0F);
      } else if (is_float()) {
        std::memcpy(flat.data() + base, data, samples * sizeof(float));
      } else if (mix->wBitsPerSample == 16) {
        const auto* pcm = reinterpret_cast<const std::int16_t*>(data);
        for (std::size_t i = 0; i < samples; ++i) flat[base + i] = pcm[i] / 32768.0F;
      } else {
        capture->ReleaseBuffer(frames);
        throw std::runtime_error("unsupported WASAPI mix format");
      }
      check(capture->ReleaseBuffer(frames), "ReleaseBuffer failed");
      check(capture->GetNextPacketSize(&packets), "GetNextPacketSize failed");
    }
    if (flat.empty()) return flat;
    return audio::downmix_mono(flat, channels);
  }
};

class WasapiMixCapture final : public IAudioCapture {
 public:
  void start() override {
    if (render_.client) return;
    try {
      const auto co = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
      owns_com_ = SUCCEEDED(co);
      ComPtr<IMMDeviceEnumerator> enumerator;
      check(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator)),
            "MMDeviceEnumerator failed");

      // 1) 系统播放的声音（原有的回路采集）
      ComPtr<IMMDevice> render_device;
      check(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &render_device),
            "default render endpoint failed");
      render_.open(render_device.Get(), AUDCLNT_STREAMFLAGS_LOOPBACK, "系统声音");
      format_ = {render_.rate, render_.channels};

      // 2) 麦克风：默认打开全部可用录音设备；也可以只用默认设备
      if (env_flag("JARVIS_MIC", true)) {
        const bool default_only = env_flag("JARVIS_MIC_DEFAULT_ONLY", false);
        if (default_only) {
          ComPtr<IMMDevice> mic_device;
          if (SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &mic_device))) {
            add_mic(mic_device.Get());
          }
        } else {
          ComPtr<IMMDeviceCollection> collection;
          if (SUCCEEDED(enumerator->EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE, &collection))) {
            UINT32 count{};
            if (SUCCEEDED(collection->GetCount(&count))) {
              for (UINT32 index = 0; index < count; ++index) {
                ComPtr<IMMDevice> mic_device;
                if (SUCCEEDED(collection->Item(index, &mic_device))) add_mic(mic_device.Get());
              }
            }
          }
        }
      }

      render_.start();
      for (auto& mic : mics_) mic->start();

      std::string summary = "麦克风采集启动：" + std::to_string(mics_.size()) + " 个设备";
      for (auto& mic : mics_) summary += " | " + mic->name;
      log_capture(summary);
    } catch (const std::exception& error) {
      log_capture(std::string("采集启动失败：") + error.what());
      stop();
      throw;
    }
  }

  void stop() noexcept override {
    render_.close();
    mics_.clear();
    if (owns_com_) { CoUninitialize(); owns_com_ = false; }
  }

  std::optional<audio::PcmBlock> next_block(std::uint32_t timeout_ms) override {
    if (!render_.client) throw std::runtime_error("audio capture not started");
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeout_ms);
    bool have = false;
    while (std::chrono::steady_clock::now() < deadline) {
      if (render_.has_packets()) { have = true; break; }
      for (auto& mic : mics_) {
        if (mic->has_packets()) { have = true; break; }
      }
      if (have) break;
      std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    if (!have) return std::nullopt;

    auto system = render_.drain_mono();
    std::vector<std::vector<float>> voices;
    float voice_peak = 0.0F;
    std::size_t frames = system.size();
    for (auto& mic : mics_) {
      auto voice = mic->drain_mono();
      if (!voice.empty() && mic->rate != render_.rate) {
        voice = audio::resample_linear(voice, mic->rate, render_.rate);
      }
      for (float sample : voice) voice_peak = std::max(voice_peak, std::abs(sample));
      frames = std::max(frames, voice.size());
      voices.push_back(std::move(voice));
    }
    // 诊断：每 5 秒记录一次实际收到的音量，便于确认麦克风有没有真的进来
    if (!system.empty() || voice_peak > 0.0F) {
      float system_peak = 0.0F;
      for (float sample : system) system_peak = std::max(system_peak, std::abs(sample));
      peak_system_ = std::max(peak_system_, system_peak);
      peak_voice_ = std::max(peak_voice_, voice_peak * mic_gain());
      const auto now = std::chrono::steady_clock::now();
      if (last_log_.time_since_epoch().count() == 0) last_log_ = now;
      if (std::chrono::duration_cast<std::chrono::milliseconds>(now - last_log_).count() >= 5000) {
        auto db = [](float peak) {
          return peak <= 0.0F ? -99.0 : 20.0 * std::log10(static_cast<double>(peak));
        };
        char buffer[160];
        std::snprintf(buffer, sizeof(buffer), "音平：系统=%.1f dB  麦克风=%.1f dB",
                      db(peak_system_), db(peak_voice_));
        log_capture(buffer);
        peak_system_ = 0.0F;
        peak_voice_ = 0.0F;
        last_log_ = now;
      }
    }
    if (frames == 0) return std::nullopt;
    system.resize(frames, 0.0F);

    const float gain = mic_gain();
    audio::PcmBlock block;
    block.format = format_;
    block.interleaved.resize(frames * format_.channels);
    for (std::size_t frame = 0; frame < frames; ++frame) {
      float mixed = system[frame];
      for (auto& voice : voices) {
        if (frame < voice.size()) mixed += voice[frame] * gain;
      }
      mixed = std::clamp(mixed, -1.0F, 1.0F);
      for (std::uint16_t channel = 0; channel < format_.channels; ++channel) {
        block.interleaved[frame * format_.channels + channel] = mixed;
      }
    }
    block.timestamp_100ns = 0;
    return block;
  }

  ~WasapiMixCapture() override { stop(); }

 private:
  void add_mic(IMMDevice* device) {
    try {
      auto mic = std::make_unique<Source>();
      mic->open(device, 0, device_friendly_name(device));
      mics_.push_back(std::move(mic));
    } catch (const std::exception& error) {
      log_capture(std::string("跳过录音设备：") + device_friendly_name(device) + "（" + error.what() + "）");
    }
  }

  bool owns_com_{};
  audio::Format format_{};
  Source render_{};
  std::vector<std::unique_ptr<Source>> mics_{};
  float peak_system_{};
  float peak_voice_{};
  std::chrono::steady_clock::time_point last_log_{};
};
} // namespace

std::unique_ptr<IAudioCapture> make_wasapi_loopback_capture() { return std::make_unique<WasapiMixCapture>(); }
} // namespace jarvis::win
#endif
