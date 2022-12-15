<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:output method="xml" indent="yes"/>

  <xsl:param name="authn-request-id"/>
  <xsl:param name="issue-instant"/>
  <xsl:param name="issuer"/>
  <xsl:param name="nameid-format"/>

  <xsl:param name="digest-algorithm"/>
  <xsl:param name="digest-value"/>

  <xsl:param name="signature-algorithm"/>
  <xsl:param name="signature-value"/>
  <xsl:param name="signature-certificate"/>

  <!-- This stylesheet is used to generate samlp:AuthnRequests.  If
       called without the $digest-algorithm or $signature-algorithm
       parameters, just the plain unsigned samlp:AuthnRequest is
       produced.  If the $digest-algorithm is present, the
       ds:Signature element will be rendered with just the
       ds:SignedInfo.  If the $signature-algorithm is also present,
       the ds:Signature and ds:KeyInfo children will be produced.

       The idea is that this transform is called three times to
       produce the completely signed request - Once to create the
       unsigned samlp:AuthnRequest, once to create the ds:SignedInfo
       with the digest value as its child and finally once with the
       signature value to create the completely signed request. -->

  <xsl:template match="/">
    <samlp:AuthnRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" Version="2.0">
      <xsl:attribute name="ID"><xsl:value-of select="$authn-request-id"/></xsl:attribute>
      <xsl:attribute name="IssueInstant"><xsl:value-of select="$issue-instant"/></xsl:attribute>
      <saml:Issuer xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion"><xsl:value-of select="$issuer"/></saml:Issuer>
      <xsl:if test="$digest-value">
        <dsig:Signature xmlns:dsig="http://www.w3.org/2000/09/xmldsig#">
          <dsig:SignedInfo>
            <dsig:CanonicalizationMethod Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>
            <dsig:SignatureMethod>
              <xsl:attribute name="Algorithm"><xsl:value-of select="$signature-algorithm"/></xsl:attribute>
            </dsig:SignatureMethod>
            <dsig:Reference>
              <xsl:attribute name="URI"><xsl:value-of select="concat('#', $authn-request-id)"/></xsl:attribute>
              <dsig:Transforms>
                <dsig:Transform Algorithm="http://www.w3.org/2000/09/xmldsig#enveloped-signature"/>
                <dsig:Transform Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>
              </dsig:Transforms>
              <dsig:DigestMethod>
                <xsl:attribute name="Algorithm"><xsl:value-of select="$digest-algorithm"/></xsl:attribute>
              </dsig:DigestMethod>
              <dsig:DigestValue><xsl:value-of select="$digest-value"/></dsig:DigestValue>
            </dsig:Reference>
          </dsig:SignedInfo>
          <xsl:if test="$signature-value">
            <dsig:SignatureValue><xsl:value-of select="$signature-value"/></dsig:SignatureValue>
            <dsig:KeyInfo>
              <dsig:X509Data>
                <dsig:X509Certificate><xsl:value-of select="$signature-certificate"/></dsig:X509Certificate>
              </dsig:X509Data>
            </dsig:KeyInfo>
          </xsl:if>
        </dsig:Signature>
      </xsl:if>
      <samlp:NameIDPolicy AllowCreate="false">
        <xsl:attribute name="Format"><xsl:value-of select="$nameid-format"/></xsl:attribute>
      </samlp:NameIDPolicy>
    </samlp:AuthnRequest>
  </xsl:template>
</xsl:stylesheet>
