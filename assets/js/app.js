import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {toByteArray, fromByteArray} from "base64-js"

let attachHook = null;
let attachment = null;
let blobURL = null;
const chunkSize = 16384;
const MAX_WIDTH = 512;
const MAX_HEIGHT = 1024;

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

function scale_ratio(w, h, max_w, max_h) {
    let wr = Math.ceil(w/max_w);
    let hr = Math.ceil(h/max_h);
    if (wr > hr)
	return wr;
    else
	return hr;
}

function scale_canvas(canvas, scale) {
    const scaledCanvas = document.createElement('canvas');
    scaledCanvas.width = canvas.width / scale;
    scaledCanvas.height = canvas.height / scale;

    scaledCanvas
	.getContext('2d')
	.drawImage(canvas, 0, 0, scaledCanvas.width, scaledCanvas.height);

    return scaledCanvas;
}

async function add_attachment(event) {
    let file = event.target.files[0];
    let canvas = document.createElement('canvas');
    const img = document.createElement('img');

    img.src = await new Promise((resolve) => {
	const reader = new FileReader();
	reader.onload = (e) => resolve(e.target.result);
	reader.readAsDataURL(file);
    });
    await new Promise((resolve) => {
	img.onload = resolve;
    });

    // draw image in canvas element
    canvas.width = img.width;
    canvas.height = img.height;
    canvas.getContext('2d').drawImage(img, 0, 0, canvas.width, canvas.height);

    if (img.width > MAX_WIDTH || img.height > MAX_HEIGHT) {
	let ratio = scale_ratio(img.width, img.height, MAX_WIDTH, MAX_HEIGHT);
	canvas = scale_canvas(canvas, ratio);
    }

    let blob = await new Promise((resolve) => {
	canvas.toBlob(resolve, 'image/jpeg');
    });

    blobURL = URL.createObjectURL(blob);
    attachment = await blob.arrayBuffer();
    attachHook.pushEvent("attach", {size: blob.size, url: blobURL});
}

function upload_attachment(offset) {
    let dlen = attachment.byteLength;
    let slen = dlen > offset + chunkSize ? chunkSize : dlen - offset;
    let slice = new Uint8Array(attachment, offset, slen);
    let chunk = fromByteArray(slice);
    attachHook.pushEvent("attachment_chunk", {chunk: chunk});
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

Hooks.ImageAttach = {
    mounted() {
	attachHook = this;
	this.el.addEventListener("change", add_attachment);
	this.handleEvent("clear_attachment", () => {
	    URL.revokeObjectURL(blobURL);
	    blobURL = null;
	    attachment = null;
	});
	this.handleEvent("read_attachment", ({offset}) => {
	    upload_attachment(offset);
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
