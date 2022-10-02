import {toByteArray, fromByteArray} from "base64-js"

export default {
    attachment: null,
    blobURL: null,
    chunkSize: 16384,
    maxWidth: 512,
    maxHeight: 1024,

    mounted() {
	let fileInput = this.el.querySelector("#image-attach");
	fileInput.addEventListener("change", (e) => this.add_attachment(e.target.files[0]));
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
	const tokens = file.type.split("/");
	if (tokens[0] === 'image') {
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
	} else {
	    this.blobURL = URL.createObjectURL(file);
	    this.attachment = await new Promise((resolve) => {
                const reader = new FileReader();
                reader.onload = (e) => resolve(e.target.result);
                reader.readAsArrayBuffer(file);
            });
	    this.pushEvent("attach", {size: file.size, name: file.name, url: this.blobURL});
	}
    },

    upload_attachment(offset) {
	let dlen = this.attachment.byteLength;
	let slen = dlen > offset + this.chunkSize ? this.chunkSize : dlen - offset;
	let slice = new Uint8Array(this.attachment, offset, slen);
	let chunk = fromByteArray(slice);
	this.pushEvent("attachment_chunk", {chunk: chunk});
    }
}
