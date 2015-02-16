'use strict';

var gulp = require('gulp');
var ghPages = require('gh-pages');
var path = require('path');
var sequence = require('run-sequence');

// load plugins
var $ = require('gulp-load-plugins')();
var connect = $.connect;

// Build variables (default to local settings)
var deploy = false;
var jekyllConfig = 'config/jekyll.local.yml';

// Sources
var sources = {
  styles: 'app/_assets/stylesheets/styles.less'
};

gulp.task('styles', function () {
  // TODO: add LESS Linting
  return gulp.src(sources.styles)
    .pipe($.plumber())
    .pipe($.sourcemaps.init())
    .pipe($.less())
    .pipe($.autoprefixer('last 2 versions'))
    .pipe($.if(deploy, $.cssmin()))
    .pipe($.sourcemaps.write('maps'))
    .pipe(gulp.dest('dist/assets'))
    .pipe($.size())
    .pipe(connect.reload());
});

gulp.task('javascripts', function () {
  return gulp.src('app/_assets/javascripts/**/*.js')
    .pipe($.plumber())
    .pipe($.jshint())
    .pipe($.jshint.reporter(require('jshint-stylish')))
    .pipe($.sourcemaps.init())
    .pipe($.if(deploy, $.uglify()))
    .pipe($.concat('app.js'))
    .pipe($.sourcemaps.write('maps'))
    .pipe(gulp.dest('dist/assets'))
    .pipe($.size())
    .pipe(connect.reload());
});

gulp.task('images', function () {
  // Just copy images
  return gulp.src('app/_assets/images/**/*')
    .pipe($.plumber())
    .pipe(gulp.dest('dist/assets/images'))
    .pipe($.size());
});

gulp.task('jekyll', function (next) {
  var command = 'bundle exec jekyll build --config ' + jekyllConfig + ' --destination dist';

  require('child_process').exec(command, function (err, stdout, stderr) {
    console.log(stdout);
    console.error(stderr);
    next(err);
  });
});

gulp.task('html', ['jekyll'], function () {
  return gulp.src('dist/**/*.html')
    .pipe($.plumber())
    .pipe($.htmlmin({
      minifyJS: true,
      minifyCSS: true,
      removeComments: true,
      collapseWhitespace: true,
      conservativeCollapse: true,
      removeEmptyAttributes: true,
      removeAttributeQuotes: true,
      collapseBooleanAttributes: true,
      removeRedundantAttributes: true,
      removeScriptTypeAttributes: true,
      removeStyleLinkTypeAttributes: true
    }))
    .pipe(gulp.dest('dist'))
    .pipe($.size())
    .pipe(connect.reload());
});

gulp.task('clean', function () {
  ghPages.clean();
  return gulp.src(['dist', '.gh-pages'])
    .pipe($.plumber())
    .pipe($.rimraf());
});

gulp.task('reload', function () {
  return gulp.src('dist')
    .pipe($.plumber())
    .pipe(connect.reload());
});

gulp.task('connect', function () {
  connect.server({
    port: 9000,
    root: 'dist',
    livereload: true
  });
});

gulp.task('watch', function () {
  gulp.watch(['app/**/*.html', 'app/**/*.txt', 'app/**/*.xml', 'app/**/*.md'], function () {
    require('run-sequence')('jekyll', 'reload');
  });
  gulp.watch('app/_assets/javascripts/**/*.js', ['javascripts']);
  gulp.watch('app/_assets/images/**/*', ['images']);
  gulp.watch(sources.styles, ['styles']);
});

gulp.task('build', ['styles', 'javascripts', 'images', 'html']);

gulp.task('build:prod', function () {
  jekyllConfig = 'config/jekyll.yml';
  sequence('build');
});

gulp.task('build:staging', function () {
  jekyllConfig = 'config/jekyll.staging.yml';
  sequence('build');
});

gulp.task('default', ['clean'], function () {
  gulp.start('build', 'connect', 'watch');
});

gulp.task('gh-pages', function (next) {
  var config = {
    message: 'Update ' + new Date().toISOString()
  };

  ghPages.publish(path.join(__dirname, 'dist'), config, next);
});

gulp.task('deploy:prod', function () {
  sequence('build:prod', 'gh-pages');
});
