# Letsencrypt certificates

The Ingresspod can be configured to fetch certificates bundle from an internal service. This internal service would be the Letsencrypt pod.

Run the Letsencrypt pod strictly as a single instance in the cluster. Configure the ingress pods to be using the `fetcher` service.

Add all domains to the letsencrypt pods config `_config/certs_list/certs.txt`. Renewals are automated and happens when 20 days is remaining on a certificate.

Useful commands:  

```sh
# After adding a domain to _config/certs_list/certs.txt
# This will make the letsencrypt pod issue a ceretificate for the domain.
snt update-config letsencrypt
git add . && commit -m "Add domain to letsencrypt"
snt sync

# Watch the logs to see the cert was issued successfully
snt logs letsencrypt

# Since it was a new certificate we want to immediately trigger the ingress pod to fetch the new certs.
# For regular renewals of certificates we just let the ingress pod fetch updates regurarly.

# This will rerun the fetcher container
snt rerun ingress fetcher

snt logs ingress
```
