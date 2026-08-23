// JavaScript adapter around Emscripten's generated zxing_dart_module.mjs.
//
// Mirrors backend_native.dart exactly: copy input into linear memory, invoke
// one coarse C ABI operation, copy output out, release all C-owned members.
// Runs inside zxing_dart_worker.mjs, never on the UI thread.

const ABI_VERSION = 1;
const READ_RESULT_SIZE = 48; // wasm32: ptr, u32, ptr, i32, 8*i32
const MATRIX_SIZE = 12; // wasm32: ptr, u32 width, u32 height

const STATUS = Object.freeze({
  ok: 0,
  notFound: 1,
  invalidArgument: 2,
  encodeError: 3,
  internalError: 4,
});

function statusMessage(status) {
  switch (status) {
    case STATUS.notFound: return 'No barcode found';
    case STATUS.invalidArgument: return 'Wasm module rejected an argument';
    case STATUS.encodeError: return 'zxing-cpp could not encode the payload';
    case STATUS.internalError: return 'Unexpected failure inside zxing-cpp';
    default: return `Unknown zxing_dart status ${status}`;
  }
}

function statusError(status, operation) {
  return Object.assign(
    new Error(`Failed to ${operation}: ${statusMessage(status)}`),
    {status},
  );
}

export async function createZxingDart(moduleFactory) {
  const module = await moduleFactory();
  const abi = module._zxd_abi_version();
  if (abi !== ABI_VERSION) {
    throw new Error(`zxing_dart ABI mismatch: expected ${ABI_VERSION}, got ${abi}`);
  }

  return {
    abiVersion: abi,
    buildInfo: module.UTF8ToString(module._zxd_build_info()),

    readBarcode(
      pixels,
      width,
      height,
      rowStride,
      pixelFormat,
      formatsMask,
      tryHarder,
    ) {
      const input = module._malloc(pixels.byteLength);
      const output = module._malloc(READ_RESULT_SIZE);
      try {
        module.HEAPU8.set(pixels, input);
        module.HEAPU8.fill(0, output, output + READ_RESULT_SIZE);
        const status = module._zxd_read(
          input,
          pixels.byteLength,
          width,
          height,
          rowStride,
          pixelFormat,
          formatsMask,
          tryHarder ? 1 : 0,
          output,
        );
        if (status === STATUS.notFound) return null;
        if (status !== STATUS.ok) throw statusError(status, 'read barcode');

        // Refresh views after the call: zxing-cpp may have grown Wasm memory.
        const words = new Uint32Array(module.HEAPU8.buffer, output, 12);
        const signedWords = new Int32Array(module.HEAPU8.buffer, output, 12);
        const bytesPointer = words[0];
        const bytesLength = words[1];
        const textPointer = words[2];
        const nativeFormat = signedWords[3];
        if (textPointer === 0 || (bytesLength !== 0 && bytesPointer === 0)) {
          throw statusError(STATUS.internalError, 'read barcode');
        }
        return {
          found: true,
          bytes: module.HEAPU8.slice(
            bytesPointer,
            bytesPointer + bytesLength,
          ),
          text: module.UTF8ToString(textPointer),
          nativeFormat,
          corners: Array.from(signedWords.slice(4, 12)),
        };
      } finally {
        module._zxd_read_result_release(output);
        module._free(output);
        module._free(input);
      }
    },

    encodeAztec(payload, eccLevel) {
      const input = module._malloc(payload.byteLength);
      const output = module._malloc(MATRIX_SIZE);
      try {
        module.HEAPU8.set(payload, input);
        module.HEAPU8.fill(0, output, output + MATRIX_SIZE);
        const status = module._zxd_encode_aztec(
          input,
          payload.byteLength,
          eccLevel,
          output,
        );
        if (status !== STATUS.ok) throw statusError(status, 'encode Aztec');

        const words = new Uint32Array(module.HEAPU8.buffer, output, 3);
        const [bitsPointer, width, height] = words;
        if (bitsPointer === 0 || width === 0 || height === 0) {
          throw statusError(STATUS.internalError, 'encode Aztec');
        }
        const rowStride = Math.floor((width + 7) / 8);
        const length = rowStride * height;
        return {
          width,
          height,
          bits: module.HEAPU8.slice(bitsPointer, bitsPointer + length),
        };
      } finally {
        module._zxd_matrix_release(output);
        module._free(output);
        module._free(input);
      }
    },
  };
}
