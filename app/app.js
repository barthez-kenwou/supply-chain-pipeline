(() => {
  const tabs = Array.from(document.querySelectorAll('[role="tab"]'));
  const panels = Array.from(document.querySelectorAll("[data-panel]"));

  function activate(id, { pushHash = true, focusTab = false } = {}) {
    tabs.forEach((tab) => {
      const on = tab.dataset.tab === id;
      tab.classList.toggle("is-active", on);
      tab.setAttribute("aria-selected", on ? "true" : "false");
      tab.tabIndex = on ? 0 : -1;
      if (on && focusTab) {
        tab.focus();
      }
    });

    panels.forEach((panel) => {
      const on = panel.dataset.panel === id;
      panel.classList.toggle("is-active", on);
      panel.hidden = !on;
      if (on) {
        requestAnimationFrame(() => observeReveals(panel));
      }
    });

    if (pushHash) {
      history.replaceState(null, "", `#${id}`);
    }
  }

  function onTabKeydown(event) {
    const current = event.currentTarget;
    const index = tabs.indexOf(current);
    if (index < 0) {
      return;
    }

    let next = -1;
    if (event.key === "ArrowRight" || event.key === "ArrowDown") {
      next = (index + 1) % tabs.length;
    } else if (event.key === "ArrowLeft" || event.key === "ArrowUp") {
      next = (index - 1 + tabs.length) % tabs.length;
    } else if (event.key === "Home") {
      next = 0;
    } else if (event.key === "End") {
      next = tabs.length - 1;
    } else {
      return;
    }

    event.preventDefault();
    activate(tabs[next].dataset.tab, { focusTab: true });
  }

  tabs.forEach((tab) => {
    tab.addEventListener("click", () => activate(tab.dataset.tab));
    tab.addEventListener("keydown", onTabKeydown);
  });

  document.querySelectorAll("[data-tab]").forEach((el) => {
    if (el.getAttribute("role") === "tab") {
      return;
    }
    el.addEventListener("click", (event) => {
      const id = el.getAttribute("data-tab");
      if (!id) {
        return;
      }
      event.preventDefault();
      activate(id);
    });
  });

  const initial = (location.hash || "#overview").replace("#", "");
  const known = panels.some((panel) => panel.dataset.panel === initial);
  activate(known ? initial : "overview", { pushHash: false });

  window.addEventListener("hashchange", () => {
    const id = location.hash.replace("#", "");
    if (panels.some((panel) => panel.dataset.panel === id)) {
      activate(id, { pushHash: false });
    }
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
      if (!el.classList.contains("is-in")) {
        io.observe(el);
      }
    });
  }

  observeReveals(document);
})();
