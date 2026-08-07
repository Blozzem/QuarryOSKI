"use strict";
const $ = selector => document.querySelector(selector);
let apiKey = sessionStorage.getItem("quarryos-key") || "";
let timer;

async function api(path, options = {}) {
  const response = await fetch(path, { ...options, headers: { "Content-Type": "application/json", "X-QuarryOS-Key": apiKey, ...(options.headers || {}) } });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.error || `HTTP ${response.status}`);
  return body;
}
function text(root, selector, value) { root.querySelector(selector).textContent = value ?? "–"; }
function ago(time) { const seconds=Math.max(0,Math.floor((Date.now()-time)/1000)); return seconds < 2 ? "jetzt" : `${seconds}s`; }
function eta(ms) { if (!Number.isFinite(ms)) return "ETA wird berechnet"; const min=Math.ceil(ms/60000); return `ETA ${min < 60 ? min+" min" : Math.floor(min/60)+"h "+min%60+"m"}`; }
function showNotice(message) { const notice=$("#notice"); notice.textContent=message; notice.hidden=!message; }

function render(turtles) {
  const container=$("#turtles"); container.replaceChildren();
  $("#fleet-title").textContent=`${turtles.length} Turtle${turtles.length===1?"":"s"}`;
  if (!turtles.length) { const empty=document.createElement("p"); empty.textContent="Noch keine Daten. Starte das Gateway in Minecraft."; container.append(empty); return; }
  for (const turtle of turtles) {
    const node=$("#turtle-template").content.firstElementChild.cloneNode(true);
    node.classList.toggle("online", turtle.online);
    text(node,".name",turtle.turtleName || `Turtle ${turtle.turtleId}`); text(node,".phase",turtle.online ? (turtle.phase || "aktiv") : "offline");
    const percent=Math.max(0,Math.min(100,Number(turtle.progressPercent)||0)); node.querySelector(".progress i").style.width=`${percent}%`;
    text(node,".percent",`${Math.floor(percent)} %`); text(node,".eta",eta(Number(turtle.estimatedRemainingMs))); text(node,".layer",turtle.layer);
    text(node,".fuel",turtle.fuel); text(node,".blocks",turtle.blocks); text(node,".seen",ago(turtle.lastSeen)); text(node,".message",turtle.message || "Keine Meldung");
    for (const button of node.querySelectorAll("[data-command]")) {
      const command=button.dataset.command;
      if (!turtle.online) button.disabled=true;
      if (command === "emergency_toggle") button.textContent=turtle.emergencyMode ? "Notfallmodus aus" : "Notfallmodus an";
      button.addEventListener("click", async () => {
        if (!confirm(`Befehl „${button.textContent}“ an ${turtle.turtleName || turtle.turtleId} senden?`)) return;
        button.disabled=true;
        try { const body={command,jobId:turtle.jobId}; if(command==="emergency_toggle") body.emergencyMode=!turtle.emergencyMode; await api(`/api/v1/turtles/${turtle.turtleId}/commands`,{method:"POST",body:JSON.stringify(body)}); showNotice("Befehl wurde an das Minecraft-Gateway übergeben."); }
        catch(error){ showNotice(error.message); } finally { button.disabled=false; }
      });
    }
    container.append(node);
  }
}
async function refresh() { try { render(await api("/api/v1/turtles")); $("#connection").textContent="Verbunden"; showNotice(""); } catch(error) { $("#connection").textContent="Verbindung gestört"; showNotice(error.message); if(error.message.includes("API key")) logout(); } }
function connect() { $("#login").hidden=true; $("#dashboard").hidden=false; clearInterval(timer); refresh(); timer=setInterval(refresh,3000); }
function logout(){ clearInterval(timer); sessionStorage.removeItem("quarryos-key"); apiKey=""; $("#dashboard").hidden=true; $("#login").hidden=false; $("#connection").textContent="Nicht verbunden"; }
$("#login-form").addEventListener("submit",event=>{event.preventDefault();apiKey=$("#key").value;sessionStorage.setItem("quarryos-key",apiKey);connect();});
$("#logout").addEventListener("click",logout); if(apiKey) connect();
