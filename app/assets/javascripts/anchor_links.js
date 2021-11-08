$(document).on("turbo:load", function () {
  $(".anchor-link").on("click", function (event) {
    navigator.clipboard.writeText(
      `${window.location.origin + window.location.pathname}#${$(this).data(
        "anchor"
      )}`
    );

    $(this).attr("aria-label", "Copied! 🎉");

    setTimeout(() => {
      $(this).attr("aria-label", "Copy link");
    }, 2000);
  });
});
