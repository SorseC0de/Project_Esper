// Each player slides in from beyond the right edge over its own stretch of the lineup's scroll, left to right;
// the chevrons fade out over the first stretch and the Kickstarter banner fades in as the row completes.
(() => {
  const lineup = document.getElementById("lineup");
  const art = lineup.querySelector(".lineup-art");
  const layers = [...lineup.querySelectorAll(".layer")];
  const chevrons = document.getElementById("chevrons");
  const chevronFadeLength = 0.08;
  const banner = document.getElementById("kickstarterBanner");
  const bannerFadeStart = 0.9;
  const slideCount = 5;
  const slideStagger = 0.18;
  const slideLength = 1 - slideStagger * (slideCount - 1);

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const clamp = (value) => Math.min(1, Math.max(0, value));
  const easeOut = (t) => 1 - Math.pow(1 - t, 3);

  let queued = false;
  function place() {
    queued = false;
    const scrollable = lineup.offsetHeight - window.innerHeight;
    const progress = clamp(-lineup.getBoundingClientRect().top / scrollable);
    chevrons.style.opacity = 1 - clamp(progress / chevronFadeLength);
    if (reduceMotion) { banner.style.opacity = 1; return; }
    const bannerShown = easeOut(clamp((progress - bannerFadeStart) / (1 - bannerFadeStart)));
    banner.style.opacity = bannerShown;
    banner.style.transform = `translateY(${(1 - bannerShown) * 12}px)`;
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
