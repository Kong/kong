data "digitalocean_project" "benchmark" {
  name = var.do_project_name
}

resource "digitalocean_project_resources" "benchmark" {
  project = data.digitalocean_project.benchmark.id
  resources = [
    digitalocean_droplet.kong.urn,
    digitalocean_droplet.db.urn,
    digitalocean_droplet.worker.urn
  ]
}