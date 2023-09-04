import {set_token, set_preferred_nick} from "../states.js";

export default {
    mounted() {
	this.handleEvent("set_token", ({token}) => {set_token(token)});
	this.handleEvent("set_preferred_nick", ({nick}) => {set_preferred_nick(nick)});
	this.handleEvent("leave", () => {
	    set_token(null);
	    this.liveSocket.disconnect(() => {clearTimeout(liveSocket.reloadWithJitterTimer)});
	});
    }
}
