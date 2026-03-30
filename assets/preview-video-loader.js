(() => {
  function getConnectionProfile() {
    const connection = navigator.connection || navigator.mozConnection || navigator.webkitConnection;
    const saveData = !!(connection && connection.saveData);
    const effectiveType = connection && typeof connection.effectiveType === "string" ? connection.effectiveType : "";
    const slowConnection = effectiveType === "slow-2g" || effectiveType === "2g" || effectiveType === "3g";
    return { saveData, slowConnection };
  }

  function getPreviewContainer(video) {
    return video.closest(".video-container");
  }

  function setPreviewVisualState(video, visualState) {
    const container = getPreviewContainer(video);
    if (!container) {
      return;
    }

    container.classList.toggle("is-loading", visualState !== "ready");
    container.classList.toggle("is-ready", visualState === "ready");
    container.dataset.previewState = visualState;
  }

  function setPreviewMode(video, mode) {
    video.dataset.mode = mode;
  }

  function refreshVisiblePlayback(videos, playPreview, pausePreview, minVisibleRatio) {
    videos.forEach((video) => {
      const rect = video.getBoundingClientRect();
      const visibleHeight = Math.min(rect.bottom, window.innerHeight) - Math.max(rect.top, 0);
      const visibleRatio = visibleHeight / Math.max(rect.height, 1);
      if (visibleRatio >= minVisibleRatio) {
        playPreview(video);
      } else {
        pausePreview(video);
      }
    });
  }

  window.setupPreviewVideos = function setupPreviewVideos(options) {
    const {
      previewMap,
      baseEagerCount = 1,
      loadMargin = 320,
      minVisibleRatio = 0.18
    } = options || {};

    const videos = Array.from(document.querySelectorAll(".project-section[data-video-id] .preview-video"));
    if (!videos.length || !previewMap) {
      return;
    }

    const { saveData, slowConnection } = getConnectionProfile();
    const eagerCount = saveData || slowConnection ? 1 : baseEagerCount;
    const previewState = new WeakMap();

    function getPreviewState(video) {
      let state = previewState.get(video);
      if (!state) {
        state = {
          eventsBound: false,
          loadRequested: false,
          loaded: false,
          shouldPlay: false,
          sourcesAttached: false
        };
        previewState.set(video, state);
      }
      return state;
    }

    function bindPreviewEvents(video) {
      const state = getPreviewState(video);
      if (state.eventsBound) {
        return;
      }

      state.eventsBound = true;
      video.addEventListener("loadeddata", () => {
        state.loaded = true;
        setPreviewVisualState(video, "ready");
        if (state.shouldPlay) {
          playPreview(video);
        } else {
          setPreviewMode(video, "ready");
        }
      });
    }

    function attachPreviewSources(video) {
      const state = getPreviewState(video);
      if (state.sourcesAttached) {
        return;
      }

      const webmSrc = video.dataset.webmSrc;

      if (webmSrc) {
        const webmSource = document.createElement("source");
        webmSource.src = webmSrc;
        webmSource.type = "video/webm";
        video.appendChild(webmSource);
      }

      state.sourcesAttached = true;
    }

    function loadPreview(video) {
      const state = getPreviewState(video);
      bindPreviewEvents(video);
      if (state.loadRequested) {
        return;
      }

      attachPreviewSources(video);
      state.loadRequested = true;
      setPreviewMode(video, "loading");
      setPreviewVisualState(video, "loading");
      video.load();
    }

    function playPreview(video) {
      const state = getPreviewState(video);
      state.shouldPlay = true;
      loadPreview(video);
      if (!state.loaded) {
        return;
      }

      video.muted = true;
      const playAttempt = video.play();
      setPreviewMode(video, "playing");
      if (playAttempt && typeof playAttempt.catch === "function") {
        playAttempt.catch(() => {
          setPreviewMode(video, "ready");
        });
      }
    }

    function pausePreview(video) {
      const state = getPreviewState(video);
      state.shouldPlay = false;
      if (!video.paused) {
        video.pause();
      }
      if (state.loaded) {
        setPreviewMode(video, "paused");
      }
    }

    videos.forEach((video, index) => {
      const section = video.closest(".project-section");
      const previewData = section ? previewMap[section.dataset.videoId] : null;
      if (!previewData) {
        return;
      }

      video.dataset.webmSrc = previewData.webm;
      video.defaultMuted = true;
      video.muted = true;
      video.loop = true;
      video.autoplay = true;
      video.playsInline = true;
      video.preload = "none";
      video.volume = 0;
      if ("disablePictureInPicture" in video) {
        video.disablePictureInPicture = true;
      }

      setPreviewMode(video, index < eagerCount ? "warming" : "pending");
      setPreviewVisualState(video, "loading");
    });

    function warmPreview(video, force = false) {
      if (!force) {
        const rect = video.getBoundingClientRect();
        if (rect.bottom < -loadMargin || rect.top > window.innerHeight + loadMargin) {
          return;
        }
      }
      loadPreview(video);
    }

    if (!("IntersectionObserver" in window)) {
      videos.forEach((video, index) => {
        warmPreview(video, true);
        if (index < eagerCount) {
          playPreview(video);
        }
      });
      return;
    }

    const warmObserver = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          warmPreview(entry.target, true);
          warmObserver.unobserve(entry.target);
        }
      });
    }, {
      root: null,
      rootMargin: `${loadMargin}px 0px`,
      threshold: 0.01
    });

    const playObserver = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting && entry.intersectionRatio >= minVisibleRatio) {
          playPreview(entry.target);
        } else {
          pausePreview(entry.target);
        }
      });
    }, {
      root: null,
      rootMargin: "0px",
      threshold: [0, minVisibleRatio, 0.45]
    });

    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        videos.forEach((video) => {
          warmObserver.observe(video);
          playObserver.observe(video);
        });
        videos.slice(0, eagerCount).forEach((video) => {
          warmPreview(video, true);
          playPreview(video);
        });
      });
    });

    document.addEventListener("visibilitychange", () => {
      if (document.hidden) {
        videos.forEach((video) => pausePreview(video));
        return;
      }
      refreshVisiblePlayback(videos, playPreview, pausePreview, minVisibleRatio);
    });
  };
})();
