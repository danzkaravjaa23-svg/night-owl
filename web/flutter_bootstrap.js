{{flutter_js}}
{{flutter_build_config}}

// Flutter's supported callback API lets startup failures reach the HTML retry
// state. The HTML overlay is removed only by the engine's first-frame event.
(function () {
  var startup = window.nightOwlStartup;
  function fail() { if (startup) startup.fail(); }
  try {
    Promise.resolve(_flutter.loader.load({
      onEntrypointLoaded: async function (engineInitializer) {
        try {
          if (startup) startup.stage('Дэлгэцийг бэлдэж байна');
          var appRunner = await engineInitializer.initializeEngine();
          if (startup) startup.stage('Аппыг нээж байна');
          await appRunner.runApp();
        } catch (_) { fail(); }
      }
    })).catch(fail);
  } catch (_) { fail(); }
})();
