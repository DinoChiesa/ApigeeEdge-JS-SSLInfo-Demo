# Demonstration of SSLInfo for JavaScript Policies

In Apigee Edge, JavaScript policies can call out to HTTP endpoints using the httpClient.
This repo includes a proxy bundle that demonstrates this behavior.

## Overview

The JavaScript code in this API Proxy will call out to a single HTTPS endpoint, using a
1-way TLS connection. This means the client (Apigee Edge) will verify the certificate of
the server endpoint.  To do that, the client needs to access a Trust store - a list of
trusted certificates that can be used to verify the trust on the certificate presented
by the remote peer. This is just basic TLS operation, the same thing your web browser
does when contacting a site like https://www.google.com .

The target server in this case is a site hosted on *.appspot.com, the domain used by Google App Engine.

To demonstrate the success case, there is a JS policy that uses a Truststore containing
the cert of the correct root Certificate Authority (CA) that can be used to verify the
target server. To demonstrate other cases, there are policies that use other
truststores, and no truststore at all.

## Disclaimer

This example is not an official Google product, nor is it part of an official Google product.

## The API Proxy

The API Proxy is just a loopback proxy. It does not use any "Target" as defined by
Apigee Edge. Just for the purposes of the demonstration it uses a JavaScript callout to
connect to [an external HTTP Service using
TLS](https://dchiesa-first-project.appspot.com/status).

Then the API proxy assigns the response for its inbound request, based on the response
received from that service. This normally happens automatically with the HTTP Target in
Apigee Edge. Designing an API Proxy to not use a Target, and to use a JavaScript policy
to connect to an HTTP Endpoint, is non-standard.

We're doing it this way only to dmeonstrate the behavior of the SSLInfo element in
the JavaScript policy configuration.

There is a single JavaScript module in the proxy.  That module, the same simple JavaScript code,
is used in 4 different JavaScript policies, each with a different configuration for
SSLInfo.

The SSLInfo element is what tells the JavaScript policy how to resolve the peer
certificates, for any outbound connections made by the JavaScript policy.  In many
cases, JavaScript policies won't do any outbound HTTPS communication, and so the SSLInfo
is irrelevant. However, for those JavaScript modules that use httpClient, the SSLInfo is
important.


### SSLInfo

The basic policy configuration for JavaScript looks like this:

```
<Javascript name='JS-1' timeLimit='2200' >
   <SSLInfo>
      <Enabled>true</Enabled>
      <ClientAuthEnabled>false</ClientAuthEnabled>
      <TrustStore>ref://reference-to-truststore</TrustStore>
   </SSLInfo>
  <ResourceURL>jsc://js-module-that-uses-httpClient.js</ResourceURL>
</Javascript>
```

And the `reference-to-truststore` needs to be the name of a reference to a TrustStore in Apigee Edge.

The Truststore is used at runtime to verify the certificate presented by the peer. Standard TLS.


### The Variants

The JavaScript connects to a *.appspot.com domain.  From openssl, the certificate chain for that site looks like this:

```
 0 s:/C=US/ST=California/L=Mountain View/O=Google LLC/CN=*.appspot.com
   i:/C=US/O=Google Trust Services/CN=Google Internet Authority G3
 1 s:/C=US/O=Google Trust Services/CN=Google Internet Authority G3
   i:/OU=GlobalSign Root CA - R2/O=GlobalSign/CN=GlobalSign
```

The first certificate, the certificate presented by the remote server (peer), is a
wildcard certificate for *.appspot.com.  This is signed by the Google Internet Authority
G3. THAT certificate is signed by GlobalSign Root CA - R2. Verifying the peer requires
verifying the chain of those two signatures.


We have different JS policies with different SSLInfo elements, each pointing to a
different truststore, each of which contains a different cert.

| policy                                                                       | truststore & certificate   | TLS Verification Result |
| ---------------------------------------------------------------------------- | -------------------------- | ----------------------- |
| [JS-GlobalSign-Root-CA-R2](./apiproxy/policies/JS-GlobalSign-Root-CA-R2.xml) | GlobalSign Root CA - R2    | success                 |
| [JS-Appspot-Wildcard-Cert](./apiproxy/policies/JS-Appspot-Wildcard-Cert.xml) | Appspot wildcard           | failure                 |
| [JS-GoDaddy-Class2-CA](./apiproxy/policies/JS-GoDaddy-Class2-CA.xml)         | GoDaddy Class2 C           | failure                 |
| [JS-no-SSLInfo.xml](./apiproxy/policies/JS-no-SSLInfo.xml)                   | -no truststore or cert-    | no verification         |


## Preparation

Setting up the various truststores is done with the help of a script in [the tools
directory](./tools). The script loads a single truststore to your organization +
environment, for each certificate found in the [certs](./certs) directory. In this way
there is a 1:1 mapping between the certs in this repo, and the truststores created by
the script.

```
cd tools
ORG=my-edge-organization
ENV=test
./provision-truststores.sh  -o $ORG -e $ENV -u $username

```

These truststores are then used by the policies in the API Proxy bundle.

NB: It is not required in Apigee Edge to store a single certificate in each
truststore. This is being done here only for the purposes of demonstration.


## Deploying the Proxy

Use the tool from the command line:

```
cd tools
npm install
./importAndDeploy.js -v -o $ORG -e $ENV -u $username -d ../
```

## Invoking the Proxy

```
APISERVER=https://$ORG-$ENV.apigee.net

# this succeeds as expected - the cert can be verified
curl -i $APISERVER/js-sslinfo-demo/t1

```

You can invoke using /t2 /t3 and /t4 as well. Turn on Apigee Edge tracing before making
the calls to see the behind-the-scenes information on the JS policy in particular.


## Teardown

First undeploy and delete the API Proxy:
```
./undeployAndDelete.js -v -o $ORG  --prefix js-sslinfo-demo -u $username
```

Then remove all the truststores:

```
./provision-truststores.sh  -o $ORG -e $ENV -u $username  -r
```

## License

This material is Copyright (c) 2018 Google LLC.
and is licensed under the [Apache 2.0 License](LICENSE). This includes the all the code as well as the API Proxy configuration.
