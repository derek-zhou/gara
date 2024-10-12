export {list_room, get_token, set_token, get_preferred_nick, set_preferred_nick};

function get_room() {
    let url = new URL(location);
    let result = url.pathname.match(/^\/room\/(.*)/);
    if (result)
	return result[1];
    else
	return null;
}

function list_room() {
    let ret = [];
    for (let i = 0; i < localStorage.length; i++) {
	let key = localStorage.key(i);
	let value = localStorage.getItem(key);
	let found = key.match(/^gara_token_(.*)/);
	if (found)
	    ret.push(found[1]);
    }
    return ret;
}

function get_token() {
    let room = get_room();
    if (room) {
	let key = "gara_token_" + room;
	return localStorage.getItem(key);
    } else {
	return null;
    }
}

function set_token(token) {
    let room = get_room();
    if (room) {
	let key = "gara_token_" + room;
	if (token)
	    localStorage.setItem(key, token);
	else
            localStorage.removeItem(key);
    }
}

function get_preferred_nick() {
    return localStorage.getItem("gara_preferred_nick");
}

function set_preferred_nick(nick) {
    localStorage.setItem("gara_preferred_nick", nick);
}
