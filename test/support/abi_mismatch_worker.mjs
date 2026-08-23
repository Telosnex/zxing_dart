self.onmessage = ({data}) => {
  self.postMessage({
    id: data.id,
    result: {
      abiVersion: 999,
      buildInfo: 'zxing_dart ABI mismatch test Worker',
    },
  });
};
