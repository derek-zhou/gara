import "./phoenix_html.js";
import {Socket} from "./phoenix.js";
import {LiveSocket} from "./phoenix_live_view.js";
import Hooks from "./_hooks/index.js";
import {list_room, get_token, get_preferred_nick} from "./states.js";

function show_progress_bar() {
    var bar = document.querySelector("div#app-progress-bar");
    bar.style.width = "100%";
    bar.style.opacity = "1";
}

function hide_progress_bar() {
    var bar = document.querySelector("div#app-progress-bar");
    bar.style.width = "0%";
    bar.style.opacity = "0";
}

function setup_list() {
    let room_list = document.querySelector("ul#room-list");
    if (room_list) {
	let rooms = list_room();
	if (rooms.length > 0) {
	    let list_notice = document.querySelector("#list-notice");
	    list_notice.removeAttribute("hidden");
	    for (let room of rooms) {
		let room_li = document.createElement('li');
		let room_link = document.createElement('a');
		let text = document.createTextNode(room);
		room_link.setAttribute("href", "/room/" + room);
		room_link.appendChild(text);
		room_li.appendChild(room_link);
		room_list.appendChild(room_li);
	    }
	}
    }
}

function local_state() {
    let ret = new Object();
    ret.timezoneOffset = new Date().getTimezoneOffset();
    ret.language = navigator.language;
    let token = get_token();
    if (token)
	ret["token"] = token;
    let preferred_nick = get_preferred_nick();
    if (preferred_nick)
	ret["preferred_nick"] = preferred_nick;
    return ret;
}

let liveSocket = new LiveSocket("/live", Socket, {hooks: Hooks, params: local_state})

// Show progress bar on live navigation and form submits
window.addEventListener("phx:page-loading-start", show_progress_bar)
window.addEventListener("phx:page-loading-stop", hide_progress_bar)

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

document.addEventListener("DOMContentLoaded", setup_list);
