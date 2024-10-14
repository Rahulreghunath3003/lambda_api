job "example" {
  datacenters = ["dc1"]
  type = "batch"

  group "example" {
    task "example" {
      driver = "raw_exec"

      config {
        command = "echo"
        args = ["Hello, Nomad!"]
      }
    }
  }
}

