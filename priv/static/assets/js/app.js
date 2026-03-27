// Phoenix LiveView initialization
// Depends on phoenix.js, phoenix_live_view.js, phoenix_html.js loaded before this script.

(function() {
  var csrfMeta = document.querySelector("meta[name='csrf-token']");
  if (!csrfMeta) return;

  // model-viewer を Phoenix LiveView から切り離して安全に初期化するフック
  var Hooks = {
    ModelViewer: {
      mounted() {
        var mv = this.el.querySelector('model-viewer');
        if (!mv) return;
        var src = mv.getAttribute('src');
        if (!src) return;
        // connectedCallback が確実に発火するよう src を再セット
        mv.removeAttribute('src');
        var self = this;
        requestAnimationFrame(function() {
          mv.setAttribute('src', src);
        });
      },
      updated() {
        // phx-update="ignore" 内なので通常は呼ばれないが念のため何もしない
      }
    }
  };

  var liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
    params: { _csrf_token: csrfMeta.getAttribute("content") },
    hooks: Hooks,
    longPollFallbackMs: 2500
  });

  liveSocket.connect();

  // Expose for debugging
  window.liveSocket = liveSocket;
})();
