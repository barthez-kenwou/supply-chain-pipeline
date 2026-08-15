(() => {
  const tabs = Array.from(document.querySelectorAll(".tab"));
  const panels = Array.from(document.querySelectorAll("[data-panel]"));

  function activate(id, { pushHash = true } = {}) {
    tabs.forEach((tab) => {
      const on = tab.dataset.tab === id;
      tab.classList.toggle("is-active", on);
      tab.setAttribute("aria-selected", on ? "true" : "false");
    });

    panels.forEach((panel) => {
      const on = panel.dataset.panel === id;
      panel.classList.toggle("is-active", on);
      if (on) {
        panel.hidden = false;
        requestAnimationFrame(() => observeReveals(panel));
      } else {
        panel.hidden = true;
      }
    });

    if (pushHash) {
      history.replaceState(null, "", `#${id}`);
    }
  }

  tabs.forEach((tab) => {
    tab.addEventListener("click", () => activate(tab.dataset.tab));
  });

  document.querySelectorAll("[data-tab]").forEach((el) => {
    if (el.classList.contains("tab")) return;
    el.addEventListener("click", (e) => {
      const id = el.getAttribute("data-tab");
      if (!id) return;
      e.preventDefault();
      activate(id);
    });
  });

  const initial = (location.hash || "#overview").replace("#", "");
  const known = panels.some((p) => p.dataset.panel === initial);
  activate(known ? initial : "overview", { pushHash: false });

  window.addEventListener("hashchange", () => {
    const id = location.hash.replace("#", "");
    if (panels.some((p) => p.dataset.panel === id)) activate(id, { pushHash: false });
  });

  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-in");
          io.unobserve(entry.target);
        }
      });
    },
    { rootMargin: "0px 0px -8% 0px", threshold: 0.12 }
  );

  function observeReveals(scope) {
    scope.querySelectorAll("[data-reveal], .step, .arch-block").forEach((el) => {
      if (!el.classList.contains("is-in")) io.observe(el);
    });
  }

  observeReveals(document);
})();
