#!/bin/sh
# validate SAML metadata according to XML schema
# eg
# curl -4s https://wayf.surfnet.nl/federate/metadata/saml20 | ./validate-metadata.sh -

#OPTIONS=--load-trace
OPTIONS="--noout --nonet"
XML_CATALOG_FILES="../lib/xsd/saml-metadata.xml" xmllint --schema saml-schema-metadata-2.0.xsd $OPTIONS $1
