// Each player slides in from beyond the right edge over its own stretch of the lineup's scroll, left to right.
(() => {
  const lineup = document.getElementById("lineup");
  const art = lineup.querySelector(".lineup-art");
  const layers = [...lineup.querySelectorAll(".layer")];
  const slideCount = 5;
  const slideStagger = 0.18;
  const slideLength = 1 - slideStagger * (slideCount - 1);

  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  const clamp = (value) => Math.min(1, Math.max(0, value));
  const easeOut = (t) => 1 - Math.pow(1 - t, 3);

  let queued = false;
  function place() {
    queued = false;
    const scrollable = lineup.offsetHeight - window.innerHeight;
    const progress = clamp(-lineup.getBoundingClientRect().top / scrollable);
    const offscreenDistance = window.innerWidth - art.getBoundingClientRect().left;
    for (const layer of layers) {
      const slide = Number(layer.style.getPropertyValue("--slide"));
      const arrived = easeOut(clamp((progress - slide * slideStagger) / slideLength));
      layer.style.transform = `translateX(${(1 - arrived) * offscreenDistance}px)`;
    }
  }
  function queue() {
    if (!queued) { queued = true; requestAnimationFrame(place); }
  }
  window.addEventListener("scroll", queue, { passive: true });
  window.addEventListener("resize", queue);
  place();
})();
