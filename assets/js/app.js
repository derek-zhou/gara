import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

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

function get_room() {
    let url = new URL(location);
    let result = url.pathname.match(/^\/room\/(.*)/);
    if (result)
	return result[1];
    else
	return null;
}

function local_state() {
    let ret = new Object();
    let room = get_room();
    ret.timezoneOffset = new Date().getTimezoneOffset();
    ret.language = navigator.language;
    if (room) {
	let key = "gara_token_" + room;
	let token = localStorage.getItem(key);
	if (token)
	    ret["token"] = token;
    }
    return ret;
}

let Hooks = new Object();

Hooks.Main = {
    mounted() {
	this.handleEvent("set_token", ({token}) => {
	    let room = get_room();
	    if (room) {
		let key = "gara_token_" + room;
		if (token)
		    localStorage.setItem(key, token);
		else
		    localStorage.removeItem(key);
	    }
	});
	this.handleEvent("leave", () => {
	    window.removeEventListener("phx:page-loading-start", show_progress_bar);
	    liveSocket.disconnect();
	});
    }
};

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
