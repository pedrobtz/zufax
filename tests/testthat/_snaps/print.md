# print() summarizes substrate and resources

    Code
      print(facts(refresh = TRUE))
    Output
      <zufax facts>
      os       Ubuntu 22.04
      runs in  Kubernetes pod default/web-6b8f9-2xkqz, containerd container
      runs on  vm (unknown)
      cpu      host 8 | effective 2
      memory   host 32G | limit 1G | available 824M
      Use facts_df() for every fact with its status and source.

---

    Code
      print(facts(refresh = TRUE))
    Output
      <zufax facts>
      os       Ubuntu 24.04
      runs in  Kubernetes pod analytics/spark-driver-7d9f-xk2lp, containerd container
      runs on  vm (hyperv), cloud azure (aks)
      cpu      host 4 | effective 1.5 (2 threads)
      memory   host 16G | limit 4G | available 3.1G
      note     2 process(es) in this container were killed for running out of memory
      Use facts_df() for every fact with its status and source.

---

    Code
      print(facts(refresh = TRUE))
    Output
      <zufax facts>
      os       Ubuntu 24.04
      runs in  no container
      runs on  bare metal
      cpu      host 4 | effective 4
      memory   host 5.8G | available 5.2G
      Use facts_df() for every fact with its status and source.

---

    Code
      print(facts(refresh = TRUE))
    Output
      <zufax facts>
      os       Ubuntu 24.04
      runs in  no container
      runs on  vm (hyperv), cloud azure
      cpu      host 4 | effective 4
      memory   host 5.8G | available 5.2G
      Use facts_df() for every fact with its status and source.

---

    Code
      print(facts(refresh = TRUE))
    Output
      <zufax facts>
      os       Ubuntu 24.04
      runs in  no container
      runs on  WSL2
      cpu      host 4 | effective 4
      memory   host 5.8G | available 5.2G
      Use facts_df() for every fact with its status and source.

---

    Code
      print(facts(refresh = TRUE))
    Output
      <zufax facts>
      os       Ubuntu 22.04
      runs in  docker container
      runs on  vm (unknown)
      cpu      host 4 | effective 1.5 (2 threads)
      memory   host 5.8G | limit 512M | available 352M
      Use facts_df() for every fact with its status and source.

