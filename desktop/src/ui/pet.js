"use strict";

// 视觉层逻辑移植自作者开源项目 Big-Guan/jarvis-codex v0.2.0（GPL-3.0）：
//   粒子场从角色图取形 → 从窗口边缘飞入组装；装甲碎片同步飞来；扫描线 + 光环 + 呼吸。
// 上层业务（气泡、对话、隐私开关、拖拽）仍沿用 AI Jarvis 原有实现。

const pet = document.querySelector("#pet");
const bubble = document.querySelector("#bubble");
const bubbleText = document.querySelector("#bubble-text");
const bubbleAction = document.querySelector("#bubble-action");
const privacyToggle = document.querySelector("#privacy-toggle");
const chat = document.querySelector("#pet-chat");
const chatClose = document.querySelector("#chat-close");
const chatForm = document.querySelector("#chat-form");
const chatInput = document.querySelector("#chat-input");
const chatSend = document.querySelector("#chat-send");
const chatMessages = document.querySelector("#chat-messages");
const characterImage = document.querySelector("#jarvis-character");
const particleCanvas = document.querySelector("#particle-field");
const particleContext = particleCanvas.getContext("2d");
const armorShardLayer = document.querySelector(".armor-shards");

const visual = { mode: "idle", level: 0 };
let outputPath = null;
let dragPointerId = null;
let dragOrigin = null;
let dragging = false;
const petContext = { scene: "other", screenBlocked: false, bubbleVisible: false, chatVisible: false };

/* ---------- 装甲碎片（19 块，来自作者项目的参数表） ---------- */
const armorShardSpecs = [
  ["polygon(35% 4%,65% 4%,63% 23%,37% 23%)", 0, -390, -8, 80],
  ["polygon(17% 9%,37% 4%,38% 31%,22% 35%)", -430, -280, -24, 0],
  ["polygon(63% 4%,83% 9%,78% 35%,62% 31%)", 430, -280, 24, 20],
  ["polygon(37% 22%,63% 22%,61% 45%,39% 45%)", 30, -320, 10, 170],
  ["polygon(20% 31%,39% 27%,43% 48%,19% 49%)", -470, -120, -32, 100],
  ["polygon(61% 27%,80% 31%,81% 49%,57% 48%)", 470, -120, 32, 120],
  ["polygon(16% 45%,43% 44%,46% 57%,20% 59%)", -520, -20, -18, 220],
  ["polygon(57% 44%,84% 45%,80% 59%,54% 57%)", 520, -20, 18, 240],
  ["polygon(42% 43%,58% 43%,59% 70%,41% 70%)", 0, 390, -10, 300],
  ["polygon(19% 56%,42% 54%,41% 73%,24% 78%)", -480, 180, -28, 280],
  ["polygon(58% 54%,81% 56%,76% 78%,59% 73%)", 480, 180, 28, 300],
  ["polygon(24% 73%,42% 68%,45% 84%,31% 88%)", -340, 330, 22, 390],
  ["polygon(58% 68%,76% 73%,69% 88%,55% 84%)", 340, 330, -22, 410],
  ["polygon(41% 68%,59% 68%,56% 88%,44% 88%)", 40, 430, 14, 470],
  ["polygon(31% 85%,45% 82%,44% 96%,36% 94%)", -250, 460, -30, 500],
  ["polygon(55% 82%,69% 85%,64% 94%,56% 96%)", 250, 460, 30, 520],
  ["polygon(43% 86%,57% 86%,56% 98%,44% 98%)", 0, 520, -12, 560],
  ["polygon(12% 25%,24% 19%,22% 45%,14% 52%)", -560, -210, -38, 180],
  ["polygon(76% 19%,88% 25%,86% 52%,78% 45%)", 560, -210, 38, 200],
];

for (const [clip, translateX, translateY, rotation, delay] of armorShardSpecs) {
  const shard = document.createElement("i");
  shard.className = "armor-shard";
  shard.style.setProperty("--shard-clip", clip);
  shard.style.setProperty("--shard-x", `${translateX}px`);
  shard.style.setProperty("--shard-y", `${translateY}px`);
  shard.style.setProperty("--shard-rotation", `${rotation}deg`);
  shard.style.setProperty("--shard-delay", `${delay}ms`);
  if (Math.abs(rotation) >= 28 || delay % 3 === 0) shard.classList.add("amber-edge");
  armorShardLayer.append(shard);
}

/* ---------- 粒子场 ---------- */
let visualParticles = [];
let formationStartedAt = -1e7;
let particleTargetBounds = { left: 0, top: 0, width: 1, height: 1 };
const FORMATION_DURATION = 3200;

function scatterParticleFromWindowEdge(particle) {
  const edge = Math.floor(Math.random() * 4);
  const inset = Math.random() * 24;
  if (edge === 0) {
    particle.fromX = inset;
    particle.fromY = Math.random() * particleCanvas.height;
  } else if (edge === 1) {
    particle.fromX = particleCanvas.width - inset;
    particle.fromY = Math.random() * particleCanvas.height;
  } else {
    particle.fromX = Math.random() * particleCanvas.width;
    particle.fromY = edge === 2 ? inset : particleCanvas.height - inset;
  }
}

function syncParticleCanvasSize() {
  const bounds = pet.getBoundingClientRect();
  const width = Math.max(1, Math.round(bounds.width));
  const height = Math.max(1, Math.round(bounds.height));
  if (particleCanvas.width !== width) particleCanvas.width = width;
  if (particleCanvas.height !== height) particleCanvas.height = height;
}

// 粒子目标点来自离线采样的坐标表（file:// 下 canvas 不能读像素，改为预生成）
function prepareVisualParticles() {
  if (!characterImage.naturalWidth) return;
  syncParticleCanvasSize();
  const petBounds = pet.getBoundingClientRect();
  const characterBounds = characterImage.getBoundingClientRect();
  const left = characterBounds.left - petBounds.left;
  const top = characterBounds.top - petBounds.top;
  particleTargetBounds = { left, top, width: characterBounds.width, height: characterBounds.height };
  const map = window.JARVIS_PARTICLE_MAP || [];
  visualParticles = [];
  for (const entry of map) {
    const [nx, ny, amber, big] = String(entry).split(",").map(Number);
    const particle = {
      fromX: 0,
      fromY: 0,
      targetX: left + nx * characterBounds.width + (Math.random() - 0.5) * 5,
      targetY: top + ny * characterBounds.height + (Math.random() - 0.5) * 5,
      size: big ? 2.6 + Math.random() * 1.8 : 0.45 + Math.random() * 1.65,
      phase: Math.random() * Math.PI * 2,
      delay: Math.random() * 0.3,
      curve: (Math.random() - 0.5) * (90 + Math.random() * 190),
      amber: amber === 1,
    };
    scatterParticleFromWindowEdge(particle);
    visualParticles.push(particle);
  }
  particlesReady = visualParticles.length > 0;
}

function startParticleFormation() {
  if (!visualParticles.length) prepareVisualParticles();
  formationStartedAt = performance.now();
  for (const particle of visualParticles) scatterParticleFromWindowEdge(particle);
}

function easeFormation(value) {
  const clamped = Math.max(0, Math.min(1, value));
  return clamped * clamped * (3 - 2 * clamped);
}

function particlePosition(particle, progress) {
  const eased = easeFormation(progress);
  const deltaX = particle.targetX - particle.fromX;
  const deltaY = particle.targetY - particle.fromY;
  const distance = Math.max(1, Math.hypot(deltaX, deltaY));
  const bend = Math.sin(eased * Math.PI) * particle.curve;
  return {
    x: particle.fromX + deltaX * eased - (deltaY / distance) * bend,
    y: particle.fromY + deltaY * eased + (deltaX / distance) * bend,
  };
}

function drawFormationEnergy(now, rawProgress) {
  if (rawProgress < 0 || rawProgress > 1.12) return;
  const progress = Math.max(0, Math.min(1, rawProgress));
  const centerX = particleTargetBounds.left + particleTargetBounds.width / 2;
  const centerY = particleTargetBounds.top + particleTargetBounds.height / 2;
  const intensity = Math.sin(progress * Math.PI);
  const outerRadius = Math.max(particleCanvas.width, particleCanvas.height) * 0.56;
  const targetRadius = Math.max(particleTargetBounds.width, particleTargetBounds.height) * 0.48;
  const radius = outerRadius + (targetRadius - outerRadius) * easeFormation(progress);

  particleContext.save();
  particleContext.globalCompositeOperation = "lighter";
  particleContext.translate(centerX, centerY);
  particleContext.scale(1, 0.72);
  for (let index = 0; index < 4; index += 1) {
    const ringRadius = radius + index * 34;
    particleContext.beginPath();
    particleContext.setLineDash([16 + index * 5, 34 + index * 7]);
    particleContext.lineDashOffset = ((index % 2 ? 1 : -1) * now) / (12 + index * 3);
    particleContext.arc(0, 0, ringRadius, 0, Math.PI * 2);
    particleContext.lineWidth = index === 0 ? 1.8 : 0.75;
    particleContext.strokeStyle = index === 2
      ? `rgba(255,155,47,${intensity * 0.48})`
      : `rgba(34,199,255,${intensity * (0.56 - index * 0.08)})`;
    particleContext.stroke();
  }
  particleContext.restore();

  const shock = Math.max(0, Math.min(1, (progress - 0.68) / 0.25));
  if (shock > 0 && shock < 1) {
    particleContext.save();
    particleContext.globalCompositeOperation = "lighter";
    particleContext.beginPath();
    particleContext.ellipse(centerX, centerY, targetRadius * (0.65 + shock * 1.35), targetRadius * (0.48 + shock * 0.95), 0, 0, Math.PI * 2);
    particleContext.strokeStyle = `rgba(134,229,255,${(1 - shock) * 0.85})`;
    particleContext.shadowColor = "#22c7ff";
    particleContext.shadowBlur = 28;
    particleContext.lineWidth = 2.4;
    particleContext.stroke();
    particleContext.restore();
  }
}

function drawParticleField(now) {
  particleContext.clearRect(0, 0, particleCanvas.width, particleCanvas.height);
  if (visualParticles.length) {
    const rawProgress = (now - formationStartedAt) / FORMATION_DURATION;
    const forming = rawProgress >= 0 && rawProgress < 1.08;
    const idleStrength = visual.mode === "speaking" ? 0.18 + visual.level * 0.48 : visual.mode === "working" ? 0.12 : 0.045;
    particleContext.globalCompositeOperation = "lighter";
    for (const particle of visualParticles) {
      const localRaw = forming ? (rawProgress - particle.delay) / (1 - particle.delay) : 1;
      const progress = Math.max(0, Math.min(1, localRaw));
      const point = particlePosition(particle, progress);
      const previous = particlePosition(particle, Math.max(0, progress - (0.035 + particle.size * 0.008)));
      const drift = forming ? 0 : Math.sin(now / 760 + particle.phase) * (1.1 + visual.level * 3.2);
      const x = point.x + drift;
      const y = point.y + Math.cos(now / 830 + particle.phase) * (forming ? 0 : 1.4);
      const alpha = forming
        ? localRaw < 0
          ? 0.12 + Math.sin(now / 180 + particle.phase) * 0.08
          : 0.34 + Math.sin(progress * Math.PI) * 0.66
        : idleStrength;
      const color = particle.amber ? "255,155,47" : "34,199,255";
      if (forming) {
        particleContext.beginPath();
        particleContext.moveTo(previous.x, previous.y);
        particleContext.lineTo(x, y);
        particleContext.strokeStyle = `rgba(${color},${alpha * (particle.size > 2.5 ? 0.62 : 0.28)})`;
        particleContext.lineWidth = particle.size > 2.5 ? 1.5 : 0.65;
        particleContext.stroke();
      }
      particleContext.beginPath();
      particleContext.arc(x, y, particle.size * (forming ? 1.3 : 1), 0, Math.PI * 2);
      particleContext.fillStyle = `rgba(${color},${alpha})`;
      particleContext.fill();
    }
    if (forming) drawFormationEnergy(now, rawProgress);
    particleContext.globalCompositeOperation = "source-over";
  }
  requestAnimationFrame(drawParticleField);
}

/* ---------- 呼吸（驱动发光和缩放） ---------- */
function breathe(now) {
  const cycle = (Math.sin((now / 3400) * Math.PI * 2) + 1) / 2;
  const speaking = visual.mode === "speaking";
  const pulse = 1 + cycle * (speaking ? 0.05 : 0.028);
  const glow = (speaking ? 0.62 : 0.42) + cycle * 0.5;
  pet.style.setProperty("--voice-pulse", pulse.toFixed(4));
  pet.style.setProperty("--voice-glow", glow.toFixed(3));
  visual.level = 0.08 + cycle * (speaking ? 0.55 : 0.22);
  requestAnimationFrame(breathe);
}

/* ---------- 组装动画 ---------- */
function startFormation() {
  prepareVisualParticles();
  pet.classList.remove("is-forming");
  void pet.offsetWidth;
  pet.classList.add("is-forming");
  startParticleFormation();
  window.setTimeout(() => pet.classList.remove("is-forming"), 3500);
}

let particlesReady = false;
function ensureParticles() {
  if (particlesReady && visualParticles.length) return;
  if (!characterImage.naturalWidth) return;
  prepareVisualParticles();
  particlesReady = visualParticles.length > 0;
}
if (characterImage.complete && characterImage.naturalWidth) ensureParticles();
characterImage.addEventListener("load", ensureParticles);
window.addEventListener("load", ensureParticles);
const readyTimer = window.setInterval(() => {
  ensureParticles();
  if (particlesReady) window.clearInterval(readyTimer);
}, 400);
window.setTimeout(() => window.clearInterval(readyTimer), 15000);
try { new ResizeObserver(() => ensureParticles()).observe(pet); } catch (_) {}
requestAnimationFrame(drawParticleField);
requestAnimationFrame(breathe);
// 视觉初始化完成就先跑一次组装，避免后面任何异常影响动画
window.setTimeout(() => { try { startFormation(); } catch (_) {} }, 60);

/* ---------- 与主程序通信（沿用原有逻辑） ---------- */
function setScreenPrivacy(enabled) {
  petContext.screenBlocked = Boolean(enabled);
  pet.dataset.screenBlocked = petContext.screenBlocked ? "true" : "false";
  pet.dataset.state = petContext.screenBlocked ? "closed" : "idle";
  pet.setAttribute("aria-label", petContext.screenBlocked ? "AI Jarvis，画面感知已暂停" : "AI Jarvis 桌宠");
  visual.mode = petContext.screenBlocked ? "idle" : visual.mode;
}

privacyToggle.addEventListener("dblclick", async event => {
  event.preventDefault();
  const previous = petContext.screenBlocked;
  setScreenPrivacy(!previous);
  if (!previous) startFormation();
  try {
    const result = await window.jarvis.toggleScreenPrivacy();
    if (typeof result?.screenBlocked === "boolean") setScreenPrivacy(result.screenBlocked);
  } catch (_) {
    setScreenPrivacy(previous);
  }
});

pet.addEventListener("pointerdown", event => {
  if (event.button !== 0) return;
  dragPointerId = event.pointerId;
  dragOrigin = { x: event.screenX, y: event.screenY };
  dragging = false;
});

pet.addEventListener("pointermove", event => {
  if (event.pointerId !== dragPointerId || !dragOrigin || dragging) return;
  if (Math.hypot(event.screenX - dragOrigin.x, event.screenY - dragOrigin.y) < 4) return;
  dragging = true;
  pet.dataset.dragging = "true";
  pet.setPointerCapture(event.pointerId);
  window.jarvis.startPetDrag();
});

function finishPetDrag(event) {
  if (event && event.pointerId !== dragPointerId) return;
  if (dragging) window.jarvis.stopPetDrag();
  if (dragPointerId !== null && pet.hasPointerCapture(dragPointerId)) pet.releasePointerCapture(dragPointerId);
  dragPointerId = null;
  dragOrigin = null;
  dragging = false;
  delete pet.dataset.dragging;
}

pet.addEventListener("pointerup", finishPetDrag);
pet.addEventListener("pointercancel", finishPetDrag);
window.addEventListener("blur", () => finishPetDrag());

function setChatVisible(visible) {
  petContext.chatVisible = Boolean(visible);
  document.body.dataset.chatOpen = petContext.chatVisible ? "true" : "false";
  chat.hidden = !petContext.chatVisible;
  visual.mode = petContext.chatVisible || petContext.bubbleVisible ? "speaking" : "idle";
  if (petContext.chatVisible) requestAnimationFrame(() => chatInput.focus());
}

function appendChatMessage(role, text, state = "ready") {
  const message = document.createElement("article");
  message.className = `chat-message ${role}`;
  message.dataset.state = state;
  const label = document.createElement("span");
  label.className = "chat-role";
  label.textContent = role === "user" ? "你" : "JARVIS";
  const content = document.createElement("p");
  content.textContent = text;
  message.append(label, content);
  chatMessages.append(message);
  chatMessages.scrollTop = chatMessages.scrollHeight;
  return message;
}

chatForm.addEventListener("submit", async event => {
  event.preventDefault();
  const message = chatInput.value.trim();
  if (!message || chatForm.dataset.busy === "true") return;
  appendChatMessage("user", message);
  chatInput.value = "";
  chatForm.dataset.busy = "true";
  chatSend.disabled = true;
  chatInput.disabled = true;
  const responseMessage = appendChatMessage("assistant", "思考中", "pending");
  try {
    const response = await window.jarvis.chat(message);
    responseMessage.dataset.state = "ready";
    responseMessage.querySelector("p").textContent = response.reply;
  } catch (error) {
    responseMessage.dataset.state = "error";
    responseMessage.querySelector("p").textContent = error.message || "回复失败，请稍后重试";
  } finally {
    delete chatForm.dataset.busy;
    chatSend.disabled = false;
    chatInput.disabled = false;
    chatMessages.scrollTop = chatMessages.scrollHeight;
    chatInput.focus();
  }
});

chatInput.addEventListener("keydown", event => {
  if (event.key !== "Enter" || event.shiftKey || event.isComposing) return;
  event.preventDefault();
  chatForm.requestSubmit();
});

chatClose.addEventListener("click", () => window.jarvis.setPetChatVisible(false));
window.addEventListener("keydown", event => {
  if (event.key === "Escape" && petContext.chatVisible) {
    event.preventDefault();
    window.jarvis.setPetChatVisible(false);
  }
});

// 与主程序通信：整段包一层 try/catch，保证任何通信异常都不会影响视觉动画
try {
  window.jarvis.onPetChatVisibility(setChatVisible);

  window.jarvis.onPetScene(scene => {
    petContext.scene = ["game", "course", "other"].includes(scene) ? scene : "other";
    pet.dataset.scene = petContext.scene;
    visual.mode = petContext.scene === "course" ? "working" : "idle";
    startFormation();
  });

  window.jarvis.onScreenPrivacy(enabled => setScreenPrivacy(enabled));

  window.jarvis.onBubble(message => {
    if (!message || !message.text) {
      bubble.hidden = true;
      petContext.bubbleVisible = false;
      outputPath = null;
      visual.mode = petContext.chatVisible ? "speaking" : "idle";
      return;
    }
    bubble.dataset.tone = message.tone || "info";
    bubbleText.textContent = message.text;
    outputPath = message.outputPath || null;
    bubbleAction.hidden = !outputPath;
    bubble.hidden = false;
    petContext.bubbleVisible = true;
    visual.mode = "speaking";
  });

  bubbleAction.addEventListener("click", () => {
    if (outputPath) window.jarvis.openOutput(outputPath);
  });
} catch (error) {
  // 桌宠视觉不依赖主程序，这里失败也要继续跑
}

startFormation();
