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

function routeStep(x, z, width) { return z*width+(z%2===0?x:width-x-1); }
function drawMap(canvas, turtle) {
  const width=Math.max(1,Number(turtle.width)||1), length=Math.max(1,Number(turtle.length)||1), total=width*length;
  const progress=Math.max(0,Math.min(total,Number(turtle.layerProgress)||0)), direction=Number(turtle.routeDirection)||1;
  const atService=Number(turtle.positionStep)<0;
  const currentX=atService?Number.NaN:Number(turtle.columnX), currentZ=atService?Number.NaN:Number(turtle.columnZ), ratio=window.devicePixelRatio||1;
  const cssWidth=Math.max(240,canvas.clientWidth), cssHeight=Math.max(140,Math.min(280,cssWidth*length/width));
  canvas.style.height=`${cssHeight}px`; canvas.width=Math.round(cssWidth*ratio); canvas.height=Math.round(cssHeight*ratio);
  const context=canvas.getContext("2d"); context.scale(ratio,ratio); context.fillStyle="#080d0f"; context.fillRect(0,0,cssWidth,cssHeight);
  const cellWidth=cssWidth/width, cellHeight=cssHeight/length, gap=Math.min(1,cellWidth*.12,cellHeight*.12);
  for(let z=0;z<length;z++) for(let x=0;x<width;x++) {
    const step=routeStep(x,z,width), complete=direction<0?step>=total-progress:step<progress, current=x===currentX&&z===currentZ;
    context.fillStyle=current?"#42e8c5":complete?"#314247":"#151d20";
    context.fillRect(x*cellWidth+gap,z*cellHeight+gap,Math.max(1,cellWidth-gap*2),Math.max(1,cellHeight-gap*2));
  }
}
function itemLabel(name) { if(!name)return "Leer"; const value=name.split(":").pop().replaceAll("_"," "); return value.charAt(0).toUpperCase()+value.slice(1); }
function renderInventory(root, turtle) {
  root.replaceChildren(); const bySlot=new Map((Array.isArray(turtle.inventory)?turtle.inventory:[]).map(item=>[Number(item.slot),item]));
  for(let slot=1;slot<=16;slot++) {
    const item=bySlot.get(slot)||{slot,count:0}, node=document.createElement("div"); node.className=`slot${item.count>0?"":" empty"}${slot===16?" reserve":""}`;
    const number=document.createElement("span"); number.className="slot-number"; number.textContent=slot===16?"16 · Reserve":String(slot);
    const name=document.createElement("span"); name.className="slot-name"; name.textContent=itemLabel(item.name); name.title=item.name||"Leer";
    const count=document.createElement("span"); count.className="slot-count"; count.textContent=item.count>0?`× ${item.count}`:"–";
    node.append(number,name,count); root.append(node);
  }
}

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
    container.append(node);
    text(node,".map-meta",`${turtle.width||"?"} × ${turtle.length||"?"} · Ebene ${turtle.layer??"?"}`); drawMap(node.querySelector(".quarry-map"),turtle);
    text(node,".inventory-meta",`${Number(turtle.inventoryUsedSlots)||0}/16 Slots · ${Number(turtle.inventoryTotalItems)||0} Items`); renderInventory(node.querySelector(".inventory"),turtle);
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
  }
}
async function refresh() { try { render(await api("/api/v1/turtles")); $("#connection").textContent="Verbunden"; showNotice(""); } catch(error) { $("#connection").textContent="Verbindung gestört"; showNotice(error.message); if(error.message.includes("API key")) logout(); } }
function connect() { $("#login").hidden=true; $("#dashboard").hidden=false; clearInterval(timer); refresh(); timer=setInterval(refresh,3000); }
function logout(){ clearInterval(timer); sessionStorage.removeItem("quarryos-key"); apiKey=""; $("#dashboard").hidden=true; $("#login").hidden=false; $("#connection").textContent="Nicht verbunden"; }
$("#login-form").addEventListener("submit",event=>{event.preventDefault();apiKey=$("#key").value;sessionStorage.setItem("quarryos-key",apiKey);connect();});
$("#logout").addEventListener("click",logout); if(apiKey) connect();
