import createModule from './zxing_dart_module.mjs';
import {createZxingDart} from './zxing_dart_loader.mjs';

let runtimePromise;

function getRuntime() {
  return runtimePromise ??= createZxingDart(createModule);
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
