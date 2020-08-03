Prerequisites:
```
cd kong-root-repo
make dev
git checkout branch/tag/release
```

Generate everything:

```
cd kong-root-repo
./scripts/autodoc
```

You can then copy the generated files to the docs.konghq.com repo manually, as follows:

```
cp autodoc/output/admin-api/admin-api.md         ../docs.konghq.com/app/$xyxversion/admin-api.md
cp autodoc/output/admin-api/db-less-admin-api.md ../docs.konghq.com/app/$xyxversion/db-less-admin-api.md
cp autodoc/output/nav/docs_nav.yml.admin-api.in  ../docs.konghq.com/autodoc-nav/docs_nav_$xyxversion.yml.admin-api.in

cp autodoc/output/cli.md ../docs.konghq.com/app/$xyxversion/cli.md

cp autodoc/output/configuration.md ../docs.konghq.com/app/$xyxversion/configuration.md

cp -r autodoc/output/pdk ../docs.konghq.com/app/$xyxversion/pdk

# Add the PDK nav to the docs nav
vim ../docs.konghq.com/app/_data/docs_nav_$xyxversion.yml
<add the contents of autodoc/output/_pdk_nav.yml in the "Plugin Development Kit" section
```



