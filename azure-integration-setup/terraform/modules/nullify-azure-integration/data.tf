# Current Entra directory (tenant) the azuread provider is authenticated
# against. Used only to surface the tenant id as an output so the customer
# can paste it into the Nullify console.
data "azuread_client_config" "current" {}
