"use strict";
const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];
const ACCENTS = { mint:["#42e8c5","66,232,197"], cyan:["#4dc9ff","77,201,255"], amber:["#ffb454","255,180,84"] };
const defaults = { refreshRate:3000, density:"comfortable", accent:"mint", motion:true };
const state = { turtles:[], selectedId:null, view:"overview", detailTab:"status", settings:loadSettings(), lastSync:null };
let apiKey=sessionStorage.getItem("quarryos-key")||"", timer, noticeTimer;

function loadSettings(){ try{return {...defaults,...JSON.parse(localStorage.getItem("quarryos-settings")||"{}")};}catch{return {...defaults};} }
function saveSettings(){ localStorage.setItem("quarryos-settings",JSON.stringify(state.settings)); applySettings(); }
function applySettings(){
  document.body.dataset.density=state.settings.density;
  document.body.dataset.motion=state.settings.motion?"full":"reduced";
  const accent=ACCENTS[state.settings.accent]||ACCENTS.mint;
  document.documentElement.style.setProperty("--accent",accent[0]); document.documentElement.style.setProperty("--accent-rgb",accent[1]);
}
async function api(path,options={}){const response=await fetch(path,{...options,headers:{"Content-Type":"application/json","X-QuarryOS-Key":apiKey,...(options.headers||{})}});const body=await response.json().catch(()=>({}));if(!response.ok)throw new Error(body.error||`HTTP ${response.status}`);return body;}
function put(root,selector,value){const element=root.querySelector(selector);if(element)element.textContent=value??"–";}
function clamp(value,min,max){return Math.max(min,Math.min(max,value));}
function progressOf(turtle){return clamp(Number(turtle.progressPercent)||0,0,100);}
function phaseLabel(phase){return ({mining:"Abbau",paused:"Pausiert",service:"Service",emergency:"Notfall",complete:"Fertig"})[phase]||phase||"Aktiv";}
function ago(time){if(!time)return "–";const seconds=Math.max(0,Math.floor((Date.now()-time)/1000));if(seconds<2)return "jetzt";if(seconds<60)return `${seconds}s`;return `${Math.floor(seconds/60)}m`;}
function eta(ms){if(!Number.isFinite(ms))return "ETA wird berechnet";const min=Math.ceil(ms/60000);return `ETA ${min<60?min+" min":Math.floor(min/60)+"h "+min%60+"m"}`;}
function number(value){return new Intl.NumberFormat("de-DE").format(Number(value)||0);}
function showNotice(message,type="info",ttl=5000){const notice=$("#notice");clearTimeout(noticeTimer);notice.textContent=message;notice.dataset.type=type;notice.hidden=!message;if(message&&ttl)noticeTimer=setTimeout(()=>notice.hidden=true,ttl);}

function setView(view){
  state.view=view;
  $$("[data-view]").forEach(button=>button.classList.toggle("active",button.dataset.view===view));
  $$("[data-page]").forEach(page=>{const active=page.dataset.page===view;page.hidden=!active;page.classList.toggle("active",active);});
  if(view==="fleet")renderFleet();
}
function routeStep(x,z,width){return z*width+(z%2===0?x:width-x-1);}
function drawMap(canvas,turtle){
  const width=Math.max(1,Number(turtle.width)||1),length=Math.max(1,Number(turtle.length)||1),total=width*length;
  const progress=clamp(Number(turtle.layerProgress)||0,0,total),direction=Number(turtle.routeDirection)||1,atService=Number(turtle.positionStep)<0;
  const currentX=atService?NaN:Number(turtle.columnX),currentZ=atService?NaN:Number(turtle.columnZ),ratio=window.devicePixelRatio||1;
  const cssWidth=Math.max(220,canvas.clientWidth),cssHeight=Math.max(150,Math.min(360,cssWidth*length/width));
  canvas.style.height=`${cssHeight}px`;canvas.width=Math.round(cssWidth*ratio);canvas.height=Math.round(cssHeight*ratio);
  const context=canvas.getContext("2d");context.scale(ratio,ratio);context.fillStyle="#080d0f";context.fillRect(0,0,cssWidth,cssHeight);
  const cellWidth=cssWidth/width,cellHeight=cssHeight/length,gap=Math.min(1,cellWidth*.12,cellHeight*.12);
  const accent=getComputedStyle(document.documentElement).getPropertyValue("--accent").trim()||"#42e8c5";
  for(let z=0;z<length;z++)for(let x=0;x<width;x++){const step=routeStep(x,z,width),complete=direction<0?step>=total-progress:step<progress,current=x===currentX&&z===currentZ;context.fillStyle=current?accent:complete?"#314247":"#151d20";context.fillRect(x*cellWidth+gap,z*cellHeight+gap,Math.max(1,cellWidth-gap*2),Math.max(1,cellHeight-gap*2));}
}
function itemLabel(name){if(!name)return "Leer";const value=name.split(":").pop().replaceAll("_"," ");return value.charAt(0).toUpperCase()+value.slice(1);}
function renderInventory(root,turtle){
  root.replaceChildren();const bySlot=new Map((Array.isArray(turtle.inventory)?turtle.inventory:[]).map(item=>[Number(item.slot),item]));
  for(let slot=1;slot<=16;slot++){const item=bySlot.get(slot)||{slot,count:0},node=document.createElement("div");node.className=`slot${item.count>0?"":" empty"}${slot===16?" reserve":""}`;const number=document.createElement("span");number.className="slot-number";number.textContent=slot===16?"16 · Reserve":String(slot);const name=document.createElement("span");name.className="slot-name";name.textContent=itemLabel(item.name);name.title=item.name||"Leer";const count=document.createElement("span");count.className="slot-count";count.textContent=item.count>0?`× ${item.count}`:"–";node.append(number,name,count);root.append(node);}
}

function renderSummary(){
  const online=state.turtles.filter(t=>t.online).length,active=state.turtles.filter(t=>t.online&&!["paused","complete"].includes(t.phase)).length;
  const warnings=state.turtles.filter(t=>t.emergencyMessage||(Number(t.fuelShortfall)||0)>0).length;
  $("#stat-online").textContent=online;$("#stat-total").textContent=`von ${state.turtles.length} Einheiten`;$("#stat-active").textContent=active;
  $("#stat-blocks").textContent=number(state.turtles.reduce((sum,t)=>sum+(Number(t.blocks)||0),0));$("#stat-warnings").textContent=warnings;
  $("#nav-count").textContent=state.turtles.length;$("#gateway-state").textContent=online?`${online} online`:state.turtles.length?"Keine Einheit online":"Warte auf Daten";
  $("#overview-status").textContent=state.turtles.length?`${online} von ${state.turtles.length} online`:"Keine Daten";
}
function renderOverview(){
  const root=$("#overview-turtles");root.replaceChildren();
  if(!state.turtles.length){root.innerHTML='<div class="empty"><strong>Noch keine Turtle-Daten</strong><span>Prüfe das Minecraft-Gateway.</span></div>';return;}
  for(const turtle of state.turtles){const node=$("#overview-unit-template").content.firstElementChild.cloneNode(true);node.classList.toggle("online",turtle.online);put(node,".name",turtle.turtleName||`Turtle ${turtle.turtleId}`);put(node,".message",turtle.online?(turtle.message||phaseLabel(turtle.phase)):"Offline · letztes Signal "+ago(turtle.lastSeen));const percent=progressOf(turtle);put(node,".percent",`${Math.floor(percent)}%`);node.querySelector(".unit-progress em").style.width=`${percent}%`;node.addEventListener("click",()=>{state.selectedId=turtle.turtleId;setView("fleet");});root.append(node);}
}
function selectedTurtle(){return state.turtles.find(t=>String(t.turtleId)===String(state.selectedId));}
function renderFleet(){
  $("#fleet-title").textContent=`${state.turtles.length} Einheit${state.turtles.length===1?"":"en"}`;
  if(state.turtles.length&&!selectedTurtle())state.selectedId=state.turtles[0].turtleId;
  const units=$("#units");units.replaceChildren();
  for(const turtle of state.turtles){const node=$("#unit-row-template").content.firstElementChild.cloneNode(true);node.classList.toggle("online",turtle.online);node.classList.toggle("active",String(turtle.turtleId)===String(state.selectedId));put(node,".name",turtle.turtleName||`Turtle ${turtle.turtleId}`);put(node,".phase",turtle.online?phaseLabel(turtle.phase):"Offline");put(node,".percent",`${Math.floor(progressOf(turtle))}%`);node.addEventListener("click",()=>{state.selectedId=turtle.turtleId;renderFleet();});units.append(node);}
  renderDetail(selectedTurtle());
}
function renderDetail(turtle){
  const root=$("#detail");root.replaceChildren();
  if(!turtle){root.innerHTML='<div class="empty card"><strong>Keine Turtle verfügbar</strong><span>Warte auf das nächste Gateway-Signal.</span></div>';return;}
  const node=$("#detail-template").content.firstElementChild.cloneNode(true),percent=progressOf(turtle);node.classList.toggle("online",turtle.online);
  put(node,".unit-id",`COMPUTER #${turtle.turtleId}`);put(node,".name",turtle.turtleName||`Turtle ${turtle.turtleId}`);put(node,".message",turtle.online?"Live verbunden":"Verbindung unterbrochen");put(node,".phase",turtle.online?phaseLabel(turtle.phase):"Offline");put(node,".percent",`${Math.floor(percent)} %`);put(node,".eta",eta(Number(turtle.estimatedRemainingMs)));node.querySelector(".hero-progress em").style.width=`${percent}%`;
  put(node,".layer",turtle.layer);put(node,".fuel",number(turtle.fuel));put(node,".blocks",number(turtle.blocks));put(node,".seen",ago(turtle.lastSeen));put(node,".dimensions",`${turtle.width||"?"} × ${turtle.length||"?"}`);put(node,".slots-used",`${Number(turtle.inventoryUsedSlots)||0} / 16`);put(node,".message-detail",turtle.emergencyMessage||turtle.message||"Keine Meldung");
  put(node,".map-meta",`${turtle.width||"?"} × ${turtle.length||"?"} · Ebene ${turtle.layer??"?"}`);put(node,".map-position",Number(turtle.positionStep)<0?"Service-Station":`X ${turtle.columnX??"?"} · Z ${turtle.columnZ??"?"}`);put(node,".inventory-meta",`${Number(turtle.inventoryTotalItems)||0} Items`);
  root.append(node);drawMap(node.querySelector(".quarry-map"),turtle);renderInventory(node.querySelector(".inventory"),turtle);
  const openTab=tab=>{state.detailTab=tab;node.querySelectorAll("[data-tab]").forEach(button=>button.classList.toggle("active",button.dataset.tab===tab));node.querySelectorAll("[data-panel]").forEach(panel=>{const active=panel.dataset.panel===tab;panel.hidden=!active;panel.classList.toggle("active",active);});if(tab==="map")requestAnimationFrame(()=>drawMap(node.querySelector(".quarry-map"),turtle));};
  node.querySelectorAll("[data-tab]").forEach(button=>button.addEventListener("click",()=>openTab(button.dataset.tab)));openTab(state.detailTab);
  node.querySelectorAll("[data-command]").forEach(button=>{const command=button.dataset.command;if(!turtle.online)button.disabled=true;if(command==="emergency_toggle")button.textContent=turtle.emergencyMode?"Notfallmodus aus":"Notfallmodus an";button.addEventListener("click",()=>sendCommand(turtle,command,button));});
}
async function sendCommand(turtle,command,button){if(!confirm(`Befehl „${button.textContent}“ an ${turtle.turtleName||turtle.turtleId} senden?`))return;button.disabled=true;try{const body={command,jobId:turtle.jobId};if(command==="emergency_toggle")body.emergencyMode=!turtle.emergencyMode;await api(`/api/v1/turtles/${turtle.turtleId}/commands`,{method:"POST",body:JSON.stringify(body)});showNotice("Befehl wurde an das Minecraft-Gateway übergeben.","success");}catch(error){showNotice(error.message,"error",0);}finally{button.disabled=false;}}
function renderAll(){renderSummary();renderOverview();if(state.view==="fleet")renderFleet();}

async function refresh(){try{state.turtles=await api("/api/v1/turtles");state.lastSync=Date.now();$("#connection").classList.add("connected");$("#connection").lastChild.textContent="Verbunden";$("#last-sync").textContent=`Sync vor ${ago(state.lastSync)}`;renderAll();}catch(error){$("#connection").classList.remove("connected");$("#connection").lastChild.textContent="Verbindung gestört";showNotice(error.message,"error",0);if(error.message.includes("API key"))logout();}}
function restartTimer(){clearInterval(timer);timer=setInterval(refresh,Number(state.settings.refreshRate)||3000);}
function connect(){$("#login").hidden=true;$("#dashboard").hidden=false;$("#logout").hidden=false;setView(state.view);refresh();restartTimer();}
function logout(){clearInterval(timer);sessionStorage.removeItem("quarryos-key");apiKey="";$("#dashboard").hidden=true;$("#login").hidden=false;$("#logout").hidden=true;$("#connection").classList.remove("connected");$("#connection").lastChild.textContent="Nicht verbunden";}
function bindSettings(){
  $("#refresh-rate").value=String(state.settings.refreshRate);$("#density").value=state.settings.density;$("#accent").value=state.settings.accent;$("#motion").checked=state.settings.motion;
  $("#refresh-rate").addEventListener("change",event=>{state.settings.refreshRate=Number(event.target.value);saveSettings();restartTimer();});
  $("#density").addEventListener("change",event=>{state.settings.density=event.target.value;saveSettings();});
  $("#accent").addEventListener("change",event=>{state.settings.accent=event.target.value;saveSettings();renderAll();});
  $("#motion").addEventListener("change",event=>{state.settings.motion=event.target.checked;saveSettings();});
}

applySettings();bindSettings();
$$("[data-view]").forEach(button=>button.addEventListener("click",()=>setView(button.dataset.view)));
$$('[data-open-fleet]').forEach(button=>button.addEventListener("click",()=>setView("fleet")));
$("#login-form").addEventListener("submit",event=>{event.preventDefault();apiKey=$("#key").value;sessionStorage.setItem("quarryos-key",apiKey);connect();});
$("#logout").addEventListener("click",logout);$("#settings-logout").addEventListener("click",logout);
if(apiKey)connect();
