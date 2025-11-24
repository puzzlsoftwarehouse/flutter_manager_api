const String uploadWorkerCode = '''
var activeRequests = {};

self.addEventListener('message', async (event) => {
  var method = event.data.method;
  var uploadUrl = event.data.uploadUrl;
  var data = event.data.data;
  var headers = event.data.headers;

  if (method === 'abort') {
    var requestId = event.data.requestId;
    var xhr = activeRequests[requestId];
    if (xhr) {
      xhr.abort();
      delete activeRequests[requestId];
    }
    return;
  }
  
  var xhr = uploadFile(method, uploadUrl, data, headers);
  activeRequests[event.data.requestId] = xhr;
});

function uploadFile(method, uploadUrl, data, headers) {
  var xhr = new XMLHttpRequest();
  var formData = new FormData();
  var uploadPercent;
  
  setData(formData, data);

  xhr.upload.addEventListener('progress', function (d) {
    if (d.lengthComputable) {
      uploadPercent = Math.floor((d.loaded / d.total) * 100);
      postMessage(uploadPercent);
    }
  }, false);

  xhr.onload = function () {
    if (xhr.status >= 200 && xhr.status < 300) {
      try {
        var response = xhr.responseText;
        if (response) {
          try {
            var jsonResponse = JSON.parse(response);
            postMessage(JSON.stringify({"data": jsonResponse}));
          } catch (e) {
            postMessage(response);
          }
        } else {
          postMessage(JSON.stringify({"data": {}}));
        }
      } catch (e) {
        postMessage(xhr.responseText || "request completed");
      }
    } else {
      try {
        var errorResponse = xhr.responseText;
        if (errorResponse) {
          try {
            var jsonError = JSON.parse(errorResponse);
            postMessage(JSON.stringify({"error": jsonError}));
          } catch (e) {
            postMessage(JSON.stringify({"error": errorResponse}));
          }
        } else {
          postMessage(JSON.stringify({"error": "Request failed with status " + xhr.status}));
        }
      } catch (e) {
        postMessage(JSON.stringify({"error": "Request failed with status " + xhr.status}));
      }
    }
  };

  xhr.onerror = function () {
    postMessage("request failed");
  };

  xhr.open(method, uploadUrl, true);
  setHeaders(xhr, headers);
  xhr.send(formData);
  return xhr;
}

function setData(formData, data) {
  for (let key in data) {
    formData.append(key, data[key]);
  }
}

function setHeaders(xhr, headers) {
  if (headers) {
    for (let key in headers) {
      if (headers.hasOwnProperty(key)) {
        xhr.setRequestHeader(key, headers[key]);
      }
    }
  }
}
''';
