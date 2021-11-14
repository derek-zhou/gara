// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "./vendor/some-package.js"
//
// Alternatively, you can `npm install some-package` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
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

function local_state() {
    let ret = new Object();
    ret.timezoneOffset = new Date().getTimezoneOffset();
    ret.language = navigator.language;
    // dump everthing from localStorage to the server side
    for (let i = 0; i < localStorage.length; i++) {
	let key = localStorage.key(i);
	let value = localStorage.getItem(key);
	let found = key.match(/^gara_(.*)/);
	if (found)
	    ret[found[1]] = value;
    }
    return ret;
}

let Hooks = new Object();

Hooks.Main = {
    mounted() {
	this.handleEvent("set_value", ({key, value}) => {
	    let local_key = "gara_" + key;
	    if (value)
		localStorage.setItem(local_key, value);
	    else
		localStorage.removeItem(local_key);
	});
	this.handleEvent("leave", ({reason}) => {	
	    window.removeEventListener("phx:page-loading-start", show_progress_bar);
	    liveSocket.disconnect();
	});
    }
};

let liveSocket = new LiveSocket("/live", Socket, {hooks: Hooks, params: local_state()})

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
