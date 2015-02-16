(function ($) {
  $('.navbar-toggle').on('click', function () {
    var $navbar = $($(this).data('target'));
    $navbar.slideToggle(150);
  });
}(jQuery));
