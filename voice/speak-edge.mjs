// 用微软 Edge 的在线神经语音合成 MP3（免费、无需密钥）
// 首选用法: node speak-edge.mjs --text-file 文本.txt --out 输出.mp3 [--voice 音色] [--rate -10%] [--pitch -6%]
// 兼容旧用法: node speak-edge.mjs "文本" 输出.mp3 [音色] [语速] [音调]
import { MsEdgeTTS, OUTPUT_FORMAT } from "msedge-tts";
import fs from "node:fs";
import path from "node:path";

const argv = process.argv.slice(2);
const opt = {};
const positional = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a.startsWith("--")) {
    opt[a.slice(2)] = argv[++i];
  } else {
    positional.push(a);
  }
}

let text = opt.text || positional[0] || "";
if (opt["text-file"]) {
  text = fs.readFileSync(opt["text-file"], "utf8").replace(/^\uFEFF/, "");
}
const outFile = opt.out || positional[1];
const voice = opt.voice || positional[2] || "zh-CN-YunyangNeural";
const rate = opt.rate || positional[3] || "";
const pitch = opt.pitch || positional[4] || "";

if (!text || !outFile) {
  console.error("用法: node speak-edge.mjs --text-file 文本.txt --out 输出.mp3 [--voice ...] [--rate -10%] [--pitch -6%]");
  process.exit(1);
}

const dir = path.dirname(path.resolve(outFile));
if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

const tts = new MsEdgeTTS();
await tts.setMetadata(voice, OUTPUT_FORMAT.AUDIO_24KHZ_48KBITRATE_MONO_MP3);
const options = {};
if (rate) options.rate = rate;
if (pitch) options.pitch = pitch;

const { audioStream } = tts.toStream(text, options);
await new Promise((resolve, reject) => {
  const out = fs.createWriteStream(outFile);
  audioStream.pipe(out);
  audioStream.on("error", reject);
  out.on("error", reject);
  out.on("finish", resolve);
});
try { await tts.close(); } catch { }
console.log("OK " + outFile);
