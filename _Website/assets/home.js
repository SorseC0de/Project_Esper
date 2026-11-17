// Each player slides in from beyond the right edge over its own stretch of the lineup's scroll, left to right;
// the opening banner and chevrons fade out over the first stretch, and the tagline and Kickstarter banner fade in as the row completes.
(() => {
  const lineup = document.getElementById("lineup");
  const art = lineup.querySelector(".lineup-art");
  const layers = [...lineup.querySelectorAll(".layer")];
  const opening = document.getElementById("opening");
  const openingFadeLength = 0.08;
  const finale = document.getElementById("finale");
  const finaleFadeStart = 0.9;
  const lineupStage = lineup.querySelector(".lineup-stage");
  const teaser = document.querySelector(".teaser");
  const teaserGapBelowFinale = 64;
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
    opening.style.opacity = 1 - clamp(progress / openingFadeLength);
    if (reduceMotion) { finale.style.opacity = 1; return; }
    const finaleShown = easeOut(clamp((progress - finaleFadeStart) / (1 - finaleFadeStart)));
    finale.style.opacity = finaleShown;
    finale.style.transform = `translateY(${(1 - finaleShown) * 12}px)`;
    const offscreenDistance = window.innerWidth - art.getBoundingClientRect().left;
    for (const layer of layers) {
      const slide = Number(layer.style.getPropertyValue("--slide"));
      const arrived = easeOut(clamp((progress - slide * slideStagger) / slideLength));
      layer.style.transform = `translateX(${(1 - arrived) * offscreenDistance}px)`;
    }
  }
  // The pinned screen keeps its full height under the finale; on a tall screen that leaves empty space before the
  // teaser, so the teaser is pulled up to sit a fixed gap under the banner.
  function placeTeaser() {
    const finaleRect = finale.getBoundingClientRect();
    const finaleShift = new DOMMatrixReadOnly(getComputedStyle(finale).transform).m42;
    const emptyBelowFinale = lineupStage.getBoundingClientRect().bottom - (finaleRect.bottom - finaleShift);
    teaser.style.marginTop = `${-Math.max(0, emptyBelowFinale - teaserGapBelowFinale)}px`;
  }

  function queue() {
    if (!queued) { queued = true; requestAnimationFrame(place); }
  }
  window.addEventListener("scroll", queue, { passive: true });
  window.addEventListener("resize", () => { placeTeaser(); queue(); });
  window.addEventListener("load", placeTeaser);
  document.fonts.ready.then(placeTeaser);
  placeTeaser();
  place();
})();
