# print() shows the Azure platform and, with cloud = TRUE, the VM

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
      print(facts(cloud = TRUE, refresh = TRUE))
    Output
      <zufax facts>
      os       Ubuntu 24.04
      runs in  Kubernetes pod analytics/spark-driver-7d9f-xk2lp, containerd container
      runs on  vm (hyperv), cloud azure (aks), node westeurope Standard_D4s_v5
      cpu      host 4 | effective 1.5 (2 threads)
      memory   host 16G | limit 4G | available 3.1G
      note     2 process(es) in this container were killed for running out of memory
      Use facts_df() for every fact with its status and source.

