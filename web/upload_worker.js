// Worker para upload de arquivo
let activeRequest = null;

self.addEventListener('message', async (event) => {
  console.log('Worker recebeu dados:', event.data);
  const { method, uploadUrl, file, data, headers } = event.data;

  try {
    switch (method) {
      case 'upload':
        if (!file) {
          throw new Error('Nenhum arquivo fornecido para upload');
        }
        activeRequest = uploadFile(uploadUrl, file, data, headers);
        break;

      case 'abort':
        abortRequest();
        break;

      default:
        throw new Error(`Método não suportado: ${method}`);
    }
  } catch (error) {
    postMessage({
      type: 'error',
      error: error.message
    });
  }
});

function uploadFile(uploadUrl, file, additionalData = {}, headers = {}) {
  const xhr = new XMLHttpRequest();
  const formData = new FormData();

  // Adiciona o arquivo ao FormData
  formData.append('file', file);

  // Adiciona dados adicionais
  Object.keys(additionalData).forEach(key => {
    formData.append(key, additionalData[key]);
  });

  // Configura listeners de progresso
  xhr.upload.addEventListener('progress', (event) => {
    if (event.lengthComputable) {
      const progress = Math.round((event.loaded / event.total) * 100);
      postMessage({
        type: 'progress',
        progress,
        loaded: event.loaded,
        total: event.total
      });
    }
  }, false);

  // Configura listener de estado
  xhr.addEventListener('readystatechange', () => {
    if (xhr.readyState === XMLHttpRequest.DONE) {
      handleResponse(xhr);
    }
  });

  // Configura listeners de erro
  xhr.addEventListener('error', () => {
    postMessage({
      type: 'error',
      error: 'Erro de rede durante o upload'
    });
    activeRequest = null;
  });

  xhr.addEventListener('timeout', () => {
    postMessage({
      type: 'error',
      error: 'Timeout durante o upload'
    });
    activeRequest = null;
  });

  xhr.addEventListener('abort', () => {
    postMessage({
      type: 'abort'
    });
    activeRequest = null;
  });

  // Abre a conexão
  xhr.open('POST', uploadUrl, true);

  // Define timeout (opcional)
  xhr.timeout = 300000; // 5 minutos

  // Define headers
  setHeaders(xhr, headers);

  // Envia o FormData
  xhr.send(formData);

  return xhr;
}

function handleResponse(xhr) {
  try {
    const contentType = xhr.getResponseHeader('Content-Type');
    let responseData;

    if (contentType && contentType.includes('application/json')) {
      responseData = JSON.parse(xhr.responseText);
    } else {
      responseData = xhr.responseText;
    }

    if (xhr.status >= 200 && xhr.status < 300) {
      postMessage({
        type: 'success',
        data: responseData,
        status: xhr.status,
        statusText: xhr.statusText
      });
    } else {
      postMessage({
        type: 'error',
        error: `Erro HTTP ${xhr.status}: ${xhr.statusText}`,
        data: responseData,
        status: xhr.status
      });
    }
  } catch (error) {
    postMessage({
      type: 'error',
      error: `Erro ao processar resposta: ${error.message}`,
      rawResponse: xhr.responseText
    });
  } finally {
    activeRequest = null;
  }
}

function abortRequest() {
  if (activeRequest) {
    activeRequest.abort();
    activeRequest = null;
    postMessage({
      type: 'abort'
    });
  }
}

function setHeaders(xhr, headers) {
  // Headers padrão para upload
  const defaultHeaders = {
    'Accept': 'application/json, text/plain, */*',
    'Cache-Control': 'no-cache'
  };

  // Mescla headers padrão com headers customizados
  const allHeaders = { ...defaultHeaders, ...headers };

  Object.keys(allHeaders).forEach(key => {
    const value = allHeaders[key];
    if (value !== null && value !== undefined) {
      xhr.setRequestHeader(key, value);
    }
  });
}

// Limpa request ativo quando o worker é terminado
self.addEventListener('beforeunload', () => {
  if (activeRequest) {
    activeRequest.abort();
    activeRequest = null;
  }
});