function handler(event) {
    var request = event.request;
    var uri = request.uri;

    // If the URI ends in a slash, append index.html
    if (uri.endsWith('/')) {
        request.uri += 'index.html';
    }
    // If there's no file extension, assume it's a directory and append index.html
    else if (!uri.includes('.')) {
        request.uri += '/index.html';
    }

    return request;
}