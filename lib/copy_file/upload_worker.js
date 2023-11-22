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
  xhr.onreadystatechange = function () {

    console.log(xhr.responseText.toString());
    if (xhr.readyState == XMLHttpRequest.DONE) {
      if(xhr.status == 200){
        postMessage(JSON.stringify({"data":JSON.parse(xhr.response)}));
      }
      else{
        postMessage(JSON.stringify({"error":JSON.parse(xhr.response)}));
      }
    }
  }

  xhr.onload = () => {
    postMessage(xhr.responseText)
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
    formData.append(key, data[key])
  }
}

function setHeaders(xhr, headers) {
  for (let key in headers) {
    xhr.setRequestHeader(key, headers[key])
  }
}