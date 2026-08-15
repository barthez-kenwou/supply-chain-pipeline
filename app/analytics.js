(() => {
  const root = globalThis;
  const plausible =
    root.plausible ||
    function plausibleStub(...args) {
      const queue = plausibleStub.q || [];
      plausibleStub.q = queue;
      queue.push(args);
    };

  plausible.init =
    plausible.init ||
    function initPlausible(options) {
      plausible.o = options || {};
    };

  root.plausible = plausible;
  plausible.init();
})();
