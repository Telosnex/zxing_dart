const overlapChannel = new BroadcastChannel('zxing_dart_pool_test');
let activeMarker = null;
let sawOverlap = false;

function markerOf(bytes) {
  return Array.from(bytes.slice(2)).join(',');
}

overlapChannel.onmessage = ({data}) => {
  if (activeMarker !== null && data === activeMarker) sawOverlap = true;
};

self.onmessage = ({data}) => {
  const {id, operation} = data;
  if (operation === 'capabilities') {
    self.postMessage({
      id,
      result: {
        abiVersion: 2,
        buildInfo: 'zxing_dart pool test Worker',
      },
    });
    return;
  }
  if (operation !== 'readBarcode') {
    self.postMessage({
      id,
      error: {status: -1, message: 'unsupported pool-test operation'},
    });
    return;
  }

  const bytes = new Uint8Array(data.pixels);
  const delay = bytes[0];
  const value = bytes[1];
  if (delay === 254) {
    self.postMessage({
      id,
      error: {status: 2, message: 'forced codec/status error'},
    });
    return;
  }
  if (delay === 255) {
    setTimeout(() => { throw new Error('forced Worker failure'); }, 0);
    return;
  }

  activeMarker = markerOf(bytes);
  sawOverlap = false;
  overlapChannel.postMessage(activeMarker);
  setTimeout(() => {
    const decoded = sawOverlap ? 2 : value;
    activeMarker = null;
    const resultBytes = Uint8Array.of(decoded);
    self.postMessage({
      id,
      result: {
        found: true,
        bytes: resultBytes,
        text: String(decoded),
        nativeFormat: 1,
        corners: [0, 0, 1, 0, 1, 1, 0, 1],
      },
    }, [resultBytes.buffer]);
  }, delay);
};
