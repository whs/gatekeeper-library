---
id: containerresourceratios
title: Container Ratios
---

# Container Ratios

## Description
Sets a maximum ratio for container resource limits to requests.
https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/

## Template
```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8scontainerratios
  annotations:
    metadata.gatekeeper.sh/title: "Container Ratios"
    metadata.gatekeeper.sh/version: 1.0.1
    description: >-
      Sets a maximum ratio for container resource limits to requests.

      https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
spec:
  crd:
    spec:
      names:
        kind: K8sContainerRatios
      validation:
        openAPIV3Schema:
          type: object
          properties:
            exemptImages:
              description: >-
                Any container that uses an image that matches an entry in this list will be excluded
                from enforcement. Prefix-matching can be signified with `*`. For example: `my-image-*`.

                It is recommended that users use the fully-qualified Docker image name (e.g. start with a domain name)
                in order to avoid unexpectedly exempting images from an untrusted repository.
              type: array
              items:
                type: string
            ratio:
              type: string
              description: >-
                The maximum allowed ratio of `resources.limits` to
                `resources.requests` on a container.
            cpuRatio:
              type: string
              description: >-
                The maximum allowed ratio of `resources.limits.cpu` to
                `resources.requests.cpu` on a container. If not specified,
                equal to `ratio`.
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8scontainerratios

        import data.lib.exempt_container.is_exempt

        missing(obj, field) = true {
          not obj[field]
        }

        missing(obj, field) = true {
          obj[field] == ""
        }

        canonify_cpu(orig) = new {
          is_number(orig)
          new := orig * 1000
        }

        canonify_cpu(orig) = new {
          not is_number(orig)
          endswith(orig, "m")
          new := to_number(replace(orig, "m", ""))
        }

        canonify_cpu(orig) = new {
          not is_number(orig)
          not endswith(orig, "m")
          regex.match("^[0-9]+$", orig)
          new := to_number(orig) * 1000
        }

        canonify_cpu(orig) = new {
          not is_number(orig)
          not endswith(orig, "m")
          regex.match("^[0-9]+[.][0-9]+$", orig)
          new := to_number(orig) * 1000
        }

        # 10 ** 21
        mem_multiple("E") = 1000000000000000000000 { true }

        # 10 ** 18
        mem_multiple("P") = 1000000000000000000 { true }

        # 10 ** 15
        mem_multiple("T") = 1000000000000000 { true }

        # 10 ** 12
        mem_multiple("G") = 1000000000000 { true }

        # 10 ** 9
        mem_multiple("M") = 1000000000 { true }

        # 10 ** 6
        mem_multiple("k") = 1000000 { true }

        # 10 ** 3
        mem_multiple("") = 1000 { true }

        # Kubernetes accepts millibyte precision when it probably shouldn't.
        # https://github.com/kubernetes/kubernetes/issues/28741
        # 10 ** 0
        mem_multiple("m") = 1 { true }

        # 1000 * 2 ** 10
        mem_multiple("Ki") = 1024000 { true }

        # 1000 * 2 ** 20
        mem_multiple("Mi") = 1048576000 { true }

        # 1000 * 2 ** 30
        mem_multiple("Gi") = 1073741824000 { true }

        # 1000 * 2 ** 40
        mem_multiple("Ti") = 1099511627776000 { true }

        # 1000 * 2 ** 50
        mem_multiple("Pi") = 1125899906842624000 { true }

        # 1000 * 2 ** 60
        mem_multiple("Ei") = 1152921504606846976000 { true }

        get_suffix(mem) = suffix {
          not is_string(mem)
          suffix := ""
        }

        get_suffix(mem) = suffix {
          is_string(mem)
          count(mem) > 0
          suffix := substring(mem, count(mem) - 1, -1)
          mem_multiple(suffix)
        }

        get_suffix(mem) = suffix {
          is_string(mem)
          count(mem) > 1
          suffix := substring(mem, count(mem) - 2, -1)
          mem_multiple(suffix)
        }

        get_suffix(mem) = suffix {
          is_string(mem)
          count(mem) > 1
          not mem_multiple(substring(mem, count(mem) - 1, -1))
          not mem_multiple(substring(mem, count(mem) - 2, -1))
          suffix := ""
        }

        get_suffix(mem) = suffix {
          is_string(mem)
          count(mem) == 1
          not mem_multiple(substring(mem, count(mem) - 1, -1))
          suffix := ""
        }

        get_suffix(mem) = suffix {
          is_string(mem)
          count(mem) == 0
          suffix := ""
        }

        canonify_mem(orig) = new {
          is_number(orig)
          new := orig * 1000
        }

        canonify_mem(orig) = new {
          not is_number(orig)
          suffix := get_suffix(orig)
          raw := replace(orig, suffix, "")
          regex.match("^[0-9]+(\\.[0-9]+)?$", raw)
          new := to_number(raw) * mem_multiple(suffix)
        }

        violation[{"msg": msg}] {
          general_violation[{"msg": msg, "field": "containers"}]
        }

        violation[{"msg": msg}] {
          general_violation[{"msg": msg, "field": "initContainers"}]
        }

        # Ephemeral containers not checked as it is not possible to set field.

        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          not is_exempt(container)
          cpu_orig := container.resources.limits.cpu
          not canonify_cpu(cpu_orig)
          msg := sprintf("container <%v> cpu limit <%v> could not be parsed", [container.name, cpu_orig])
        }

        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          not is_exempt(container)
          mem_orig := container.resources.limits.memory
          not canonify_mem(mem_orig)
          msg := sprintf("container <%v> memory limit <%v> could not be parsed", [container.name, mem_orig])
        }

        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          not is_exempt(container)
          cpu_orig := container.resources.requests.cpu
          not canonify_cpu(cpu_orig)
          msg := sprintf("container <%v> cpu request <%v> could not be parsed", [container.name, cpu_orig])
        }

        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          not is_exempt(container)
          mem_orig := container.resources.requests.memory
          not canonify_mem(mem_orig)
          msg := sprintf("container <%v> memory request <%v> could not be parsed", [container.name, mem_orig])
        }

        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          not is_exempt(container)
          not container.resources
          msg := sprintf("container <%v> has no resource limits", [container.name])
        }

        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          not is_exempt(container)
          not container.resources.limits
          msg := sprintf("container <%v> has no resource limits", [container.name])
        }

        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          not is_exempt(container)
          missing(container.resources.limits, "cpu")
          msg := sprintf("container <%v> has no cpu limit", [container.name])
        }

        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          not is_exempt(container)
          missing(container.resources.limits, "memory")
          msg := sprintf("container <%v> has no memory limit", [container.name])
        }

        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          not is_exempt(container)
          not container.resources.requests
          msg := sprintf("container <%v> has no resource requests", [container.name])
        }

        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          not is_exempt(container)
          missing(container.resources.requests, "cpu")
          msg := sprintf("container <%v> has no cpu request", [container.name])
        }

        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          not is_exempt(container)
          missing(container.resources.requests, "memory")
          msg := sprintf("container <%v> has no memory request", [container.name])
        }

        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          not is_exempt(container)
          cpu_limits_orig := container.resources.limits.cpu
          cpu_limits := canonify_cpu(cpu_limits_orig)
          cpu_requests_orig := container.resources.requests.cpu
          cpu_requests := canonify_cpu(cpu_requests_orig)
          cpu_ratio := object.get(input.parameters, "cpuRatio", input.parameters.ratio)
          to_number(cpu_limits) > to_number(cpu_ratio) * to_number(cpu_requests)
          msg := sprintf("container <%v> cpu limit <%v> is higher than the maximum allowed ratio of <%v>", [container.name, cpu_limits_orig, cpu_ratio])
        }

        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          not is_exempt(container)
          mem_limits_orig := container.resources.limits.memory
          mem_requests_orig := container.resources.requests.memory
          mem_limits := canonify_mem(mem_limits_orig)
          mem_requests := canonify_mem(mem_requests_orig)
          mem_ratio := input.parameters.ratio
          to_number(mem_limits) > to_number(mem_ratio) * to_number(mem_requests)
          msg := sprintf("container <%v> memory limit <%v> is higher than the maximum allowed ratio of <%v>", [container.name, mem_limits_orig, mem_ratio])
        }
      libs:
        - |
          package lib.exempt_container

          is_exempt(container) {
              exempt_images := object.get(object.get(input, "parameters", {}), "exemptImages", [])
              img := container.image
              exemption := exempt_images[_]
              _matches_exemption(img, exemption)
          }

          _matches_exemption(img, exemption) {
              not endswith(exemption, "*")
              exemption == img
          }

          _matches_exemption(img, exemption) {
              endswith(exemption, "*")
              prefix := trim_suffix(exemption, "*")
              startswith(img, prefix)
          }

```

### Usage
```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/containerresourceratios/template.yaml
```
## Examples
<details>
<summary>memory-ratio-only</summary><blockquote>

<details>
<summary>constraint</summary>

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerRatios
metadata:
  name: container-must-meet-ratio
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
  parameters:
    ratio: "2"

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/containerresourceratios/samples/container-must-meet-ratio/constraint.yaml
```

</details>

<details>
<summary>example-allowed</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: opa-disallowed
  labels:
    owner: me.agilebank.demo
spec:
  containers:
    - name: opa
      image: openpolicyagent/opa:0.9.2
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"
      resources:
        limits:
          cpu: "200m"
          memory: "200Mi"
        requests:
          cpu: "100m"
          memory: "100Mi"

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/containerresourceratios/samples/container-must-meet-ratio/example_allowed.yaml
```

</details>
<details>
<summary>example-disallowed</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: opa-disallowed
  labels:
    owner: me.agilebank.demo
spec:
  containers:
    - name: opa
      image: openpolicyagent/opa:0.9.2
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"
      resources:
        limits:
          cpu: "800m"
          memory: "2Gi"
        requests:
          cpu: "100m"
          memory: "100Mi"

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/containerresourceratios/samples/container-must-meet-ratio/example_disallowed.yaml
```

</details>


</blockquote></details><details>
<summary>memory-and-cpu-ratios</summary><blockquote>

<details>
<summary>constraint</summary>

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerRatios
metadata:
  name: container-must-meet-memory-and-cpu-ratio
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
  parameters:
    ratio: "1"
    cpuRatio: "10"

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/containerresourceratios/samples/container-must-meet-memory-and-cpu-ratio/constraint.yaml
```

</details>

<details>
<summary>example-allowed</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: opa-allowed
  labels:
    owner: me.agilebank.demo
spec:
  containers:
    - name: opa
      image: openpolicyagent/opa:0.9.2
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"
      resources:
        limits:
          cpu: "4"
          memory: "2Gi"
        requests:
          cpu: "1"
          memory: "2Gi"

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/containerresourceratios/samples/container-must-meet-memory-and-cpu-ratio/example_allowed.yaml
```

</details>
<details>
<summary>example-disallowed</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: opa-disallowed
  labels:
    owner: me.agilebank.demo
spec:
  containers:
    - name: opa
      image: openpolicyagent/opa:0.9.2
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"
      resources:
        limits:
          cpu: "4"
          memory: "2Gi"
        requests:
          cpu: "100m"
          memory: "2Gi"

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/containerresourceratios/samples/container-must-meet-memory-and-cpu-ratio/example_disallowed.yaml
```

</details>


</blockquote></details>