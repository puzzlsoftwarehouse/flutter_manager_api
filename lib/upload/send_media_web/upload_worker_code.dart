const String uploadWorkerCode = '''
var activeRequests = {};

self.addEventListener('message', function (event) {
  var method = event.data.method;
  var requestId = event.data.requestId;

  if (method === 'abort') {
    var xhr = activeRequests[requestId];
    if (xhr) {
      xhr.abort();
      delete activeRequests[requestId];
    }
    return;
  }

  var uploadUrl = event.data.uploadUrl;
  var data = event.data.data;
  var headers = event.data.headers;
  var xhr = uploadFile(method, uploadUrl, data, headers, requestId);
  activeRequests[requestId] = xhr;
});

function uploadFile(method, uploadUrl, data, headers, requestId) {
  var xhr = new XMLHttpRequest();
  var formData = new FormData();

  setData(formData, data);

  xhr.upload.addEventListener('progress', function (event) {
    if (event.lengthComputable) {
      var uploadPercent = Math.floor((event.loaded / event.total) * 100);
      postMessage(JSON.stringify({
        kind: 'progress',
        requestId: requestId,
        value: uploadPercent
      }));
    }
  }, false);

  xhr.onload = function () {
    delete activeRequests[requestId];

    if (xhr.status >= 200 && xhr.status < 300) {
      var responseBody = {};
      if (xhr.responseText) {
        try {
          responseBody = JSON.parse(xhr.responseText);
        } catch (error) {
          postMessage(JSON.stringify({
            kind: 'failure',
            requestId: requestId,
            exception_code: '000',
            detail: 'Invalid upload response'
          }));
          return;
        }
      }
      postMessage(JSON.stringify({
        kind: 'complete',
        requestId: requestId,
        data: responseBody
      }));
      return;
    }

    postMessage(JSON.stringify(parseFailurePayload(xhr, requestId)));
  };

  xhr.onerror = function () {
    delete activeRequests[requestId];
    postMessage(JSON.stringify({
      kind: 'failure',
      requestId: requestId,
      exception_code: 'noConnection',
      detail: 'The XMLHttpRequest onError callback was called. This usually indicates a network or CORS failure.'
    }));
  };

  xhr.ontimeout = function () {
    delete activeRequests[requestId];
    postMessage(JSON.stringify({
      kind: 'failure',
      requestId: requestId,
      exception_code: 'timeout',
      detail: 'tempo excedido'
    }));
  };

  xhr.onabort = function () {
    delete activeRequests[requestId];
    postMessage(JSON.stringify({
      kind: 'failure',
      requestId: requestId,
      exception_code: 'cancel',
      detail: 'canceled by user'
    }));
  };

  xhr.open(method, uploadUrl, true);
  xhr.timeout = 1800000;
  setHeaders(xhr, headers);
  xhr.send(formData);
  return xhr;
}

function parseFailurePayload(xhr, requestId) {
  var statusCode = String(xhr.status);
  var detail = xhr.statusText || 'Request failed';

  if (xhr.status === 413) {
    detail = 'This file is larger than the server upload limit.';
  }

  if (xhr.responseText) {
    try {
      var parsed = JSON.parse(xhr.responseText);
      return {
        kind: 'failure',
        requestId: requestId,
        exception_code: parsed.exception_code ? String(parsed.exception_code) : statusCode,
        detail: parsed.detail || parsed.message || detail
      };
    } catch (error) {
      detail = xhr.responseText;
    }
  }

  return {
    kind: 'failure',
    requestId: requestId,
    exception_code: statusCode,
    detail: detail
  };
}

function setData(formData, data) {
  for (var key in data) {
    if (!Object.prototype.hasOwnProperty.call(data, key)) {
      continue;
    }
    var entry = data[key];
    if (entry && entry.blob) {
      formData.append(key, entry.blob, entry.name || 'file');
      continue;
    }
    formData.append(key, entry);
  }
}

function setHeaders(xhr, headers) {
  if (!headers) {
    return;
  }
  for (var key in headers) {
    if (!Object.prototype.hasOwnProperty.call(headers, key)) {
      continue;
    }
    if (key.toLowerCase() === 'content-type') {
      continue;
    }
    xhr.setRequestHeader(key, headers[key]);
  }
}
''';
