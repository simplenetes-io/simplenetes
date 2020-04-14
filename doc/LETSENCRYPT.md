# Letsencrypt certificates

The Ingresspod can be configured to fetch certificates bundle from an internal service. This internal service would be the Letsencrypt pod.

Run the Letsencrypt pod strictly as a single instance in the cluster. Configure the ingress pods to be using the `fetcher` service.

Add all domains to the letsencrypt pods config `certs_list/certs.txt`. Renewals are automated and happens when 20 days is remaining on a certificate.

