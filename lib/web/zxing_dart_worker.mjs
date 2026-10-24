// The query of this worker URL holds the webVersion of the package
// (kiln ADR 002 D7). Each file that the worker loads gets the same
// query, so a browser does not use a cached file of another version.
const query = new URL(import.meta.url).search;

let runtimePromise;

async function createRuntime() {
  const [{default: createModule}, {createZxingDart}] = await Promise.all([
    import(`./zxing_dart_module.mjs${query}`),
    import(`./zxing_dart_loader.mjs${query}`),
  ]);
  return createZxingDart(() =>
    createModule({locateFile: (path, prefix) => `${prefix}${path}${query}`}),
  );
}

function getRuntime() {
  return runtimePromise ??= createRuntime();
}

self.onmessage = async ({data}) => {
  const {id, operation} = data;
  try {
    const runtime = await getRuntime();
    if (operation === 'capabilities') {
      self.postMessage({
        id,
        result: {
          abiVersion: runtime.abiVersion,
          buildInfo: runtime.buildInfo,
          canEncodeDataMatrix: runtime.canEncodeDataMatrix,
        },
      });
      return;
    }
    if (operation === 'readBarcode') {
      const result = runtime.readBarcode(
        new Uint8Array(data.pixels),
        data.width,
        data.height,
        data.rowStride,
        data.pixelFormat,
        data.formatsMask,
        data.tryHarder,
      );
      if (result === null) {
        self.postMessage({id, result: {found: false}});
      } else {
        self.postMessage({id, result}, [result.bytes.buffer]);
      }
      return;
    }
    if (operation === 'encodeAztec') {
      const result = runtime.encodeAztec(
        new Uint8Array(data.payload),
        data.errorCorrectionPercent,
      );
      self.postMessage({id, result}, [result.bits.buffer]);
      return;
    }
    if (operation === 'encodeDataMatrix') {
      const result = runtime.encodeDataMatrix(new Uint8Array(data.payload));
      self.postMessage({id, result}, [result.bits.buffer]);
      return;
    }
    if (operation === 'resourceUrls') {
      // For the browser test of the ?v= query on every loaded file.
      self.postMessage({
        id,
        result: performance.getEntriesByType('resource').map((e) => e.name),
      });
      return;
    }
    throw new Error(`Unknown zxing_dart operation: ${operation}`);
  } catch (error) {
    self.postMessage({
      id,
      error: {
        status: error.status ?? -1,
        message: error.message ?? String(error),
      },
    });
  }
};
