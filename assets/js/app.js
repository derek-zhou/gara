import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {toByteArray, fromByteArray} from "base64-js"

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

Hooks.ImageAttach = {
    attachment: null,
    blobURL: null,
    chunkSize: 16384,
    maxWidth: 512,
    maxHeight: 1024,

    mounted() {
	this.el.addEventListener("change", (e) => this.add_attachment(e.target.files[0]));
	this.handleEvent("clear_attachment", () => {
	    URL.revokeObjectURL(blobURL);
	    this.blobURL = null;
	    this.attachment = null;
	});
	this.handleEvent("read_attachment", ({offset}) => {
	    this.upload_attachment(offset);
	});
    },

    scale_ratio(w, h) {
	let wr = Math.ceil(w/this.maxWidth);
	let hr = Math.ceil(h/this.maxHeight);
	if (wr > hr)
	    return wr;
	else
	    return hr;
    },

    scale_canvas(canvas, scale) {
	const scaledCanvas = document.createElement('canvas');
	scaledCanvas.width = canvas.width / scale;
	scaledCanvas.height = canvas.height / scale;
	
	scaledCanvas
	    .getContext('2d')
	    .drawImage(canvas, 0, 0, scaledCanvas.width, scaledCanvas.height);
	
	return scaledCanvas;
    },

    async add_attachment(file) {
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

	if (img.width > this.maxWidth || img.height > this.maxHeight) {
	    let ratio = this.scale_ratio(img.width, img.height);
	    canvas = this.scale_canvas(canvas, ratio);
	}

	let blob = await new Promise((resolve) => {
	    canvas.toBlob(resolve, 'image/jpeg');
	});

	this.blobURL = URL.createObjectURL(blob);
	this.attachment = await blob.arrayBuffer();
	this.pushEvent("attach", {size: blob.size, url: this.blobURL});
    },

    upload_attachment(offset) {
	let dlen = this.attachment.byteLength;
	let slen = dlen > offset + this.chunkSize ? this.chunkSize : dlen - offset;
	let slice = new Uint8Array(this.attachment, offset, slen);
	let chunk = fromByteArray(slice);
	this.pushEvent("attachment_chunk", {chunk: chunk});
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
