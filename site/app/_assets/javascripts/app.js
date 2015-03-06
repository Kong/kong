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

  // Form on downloads page

  Parse.initialize("ZFqEMoCQSm0K4piYYdstraJDOl0a80tJB7R0tR49", "SdqL88SikiiftwBjEGfRb4SmbghTIycZ2kfy7Jb0");

  $('.subscribe-form').on('submit', function (e) {
    e.preventDefault();

    var $form = $(this);
    var data = $form.serializeArray();
    var Subscription = Parse.Object.extend('Subscription');
    var subscription = new Subscription();

    for (var i = 0; i < data.length; i++) {
      subscription.set(data[i].name, data[i].value);
    }

    subscription.save(null, {
      success: function () {
        $form.fadeOut(300, function () {
          $('.success-message').fadeIn(300);
        });
      },
      error: function () {
        $form.fadeOut(300, function () {
          $('.error-message').fadeIn(300);
        });
      }
    });
  });
}(jQuery));
