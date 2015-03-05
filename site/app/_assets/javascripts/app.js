(function ($) {
  $('.navbar-toggle').on('click', function () {
    var $navbar = $($(this).data('target'));
    $navbar.slideToggle(150);
  });

  // Page section on contribute page

  $('.toggle-page-section').on('click', function (e) {
    e.preventDefault();
    var $link = $(this);

    $link.parent().next('.page-section').stop().slideToggle(300, function () {
      $link.toggleClass('active');
    });
  });

  // Tabs on download page

  var $tabs = $('.tab-list li');
  var $tabPanes = $('.tab-pane');

  $tabs.on('click', function (e) {
    e.preventDefault();

    $tabs.removeClass('active').filter(this).addClass('active');
    $tabPanes.removeClass('active').filter($(this).find('a').attr('href')).addClass('active');
  });
}(jQuery));
