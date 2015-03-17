'use strict';

var gulp = require('gulp');
var path = require('path');
var glob = require('glob');
var ghPages = require('gh-pages');
var sequence = require('run-sequence');

// load gulp plugins
var $ = require('gulp-load-plugins')();
var connect = $.connect;

// Build variables (default to local config)
var jekyllConfigs = {
  PROD: 'config/jekyll.yml',
  LOCAL: 'config/jekyll.local.yml'
};

var jekyllConfig = jekyllConfigs.LOCAL;

// Sources
var sources = {
  styles: 'app/_assets/stylesheets/index.less',
  js: 'app/_assets/javascripts/**/*.js',
  images: 'app/_assets/images/**/*'
};

gulp.task('styles', function () {
  // TODO: add LESS linting

  // thibaultcha:
  // 1. gulp-less has plugins (minifier and prefixer) we can run in $.less(plugins: [clean, prefix])
  // but they throw errors if we use them. Let's use gulp-autoprefixer and gulp-minify-css.
  //
  // 2. If we want to use uncss, we need to minify after it runs, otherwise it unminifies the css
  // another reason not to use gulp-less plugins.
  //
  // 3. the source maps still don't work if used along with gulp-autoprefixer
  //
  // 4. uncss and gulpminify-css seem to behave fine and is not having an impact on sourcemaps
  //
  // 5. fuck this shit.
  return gulp.src(sources.styles)
    .pipe($.plumber())
    .pipe($.sourcemaps.init())
    .pipe($.less())
    .pipe($.uncss({ html: glob.sync('dist/**/*.html') }))
    .pipe($.autoprefixer())
    .pipe($.minifyCss())
    .pipe($.sourcemaps.write('maps'))
    .pipe($.rename('styles.css'))
    .pipe(gulp.dest('dist/assets/'))
    .pipe($.size())
    .pipe(connect.reload());
});

gulp.task('javascripts', function () {
  return gulp.src(sources.js)
    .pipe($.plumber())
    .pipe($.jshint())
    .pipe($.jshint.reporter(require('jshint-stylish')))
    .pipe($.sourcemaps.init())
    .pipe($.concat('app.js'))
    .pipe($.uglify())
    .pipe($.sourcemaps.write('maps'))
    .pipe(gulp.dest('dist/assets'))
    .pipe($.size())
    .pipe(connect.reload());
});

gulp.task('images', function () {
  // Just copy images
  return gulp.src(sources.images)
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
      collapseBooleanAttributes: true,
      removeScriptTypeAttributes: true,
      removeStyleLinkTypeAttributes: true
    }))
    .pipe(gulp.dest('dist'))
    .pipe($.size())
    .pipe(connect.reload());
});

gulp.task('clean', function (cb) {
  ghPages.clean();
  require('del')(['dist', '.gh-pages'], cb);
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
    livereload: true,
    fallback: 'dist/404/index.html'
  });
});

gulp.task('watch', function () {
  gulp.watch(['app/**/*.html', 'app/**/*.txt', 'app/**/*.xml', 'app/**/*.md'], function () {
    sequence('jekyll', 'reload');
  });
  gulp.watch('app/_assets/javascripts/**/*.js', ['javascripts']);
  gulp.watch('app/_assets/images/**/*', ['images']);
  gulp.watch('app/_assets/stylesheets/**/*.{less,css}', ['styles']);
});

gulp.task('build', ['javascripts', 'images'], function () {
  sequence('html', 'styles');
});

gulp.task('build:prod', function () {
  jekyllConfig = jekyllConfigs.PROD;
  sequence('build');
});

gulp.task('default', ['clean'], function () {
  sequence('build', 'connect', 'watch');
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
