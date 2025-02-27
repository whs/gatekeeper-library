---
id: ephemeralstoragelimit
title: Container ephemeral storage limit
---

# Container ephemeral storage limit

## Description
Requires containers to have an ephemeral storage limit set and constrains the limit to be within the specified maximum values.
https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/

## Template
```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8scontainerephemeralstoragelimit
  annotations:
    metadata.gatekeeper.sh/title: "Container ephemeral storage limit"
    metadata.gatekeeper.sh/version: 1.0.2
    description: >-
      Requires containers to have an ephemeral storage limit set and constrains
      the limit to be within the specified maximum values.

      https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
spec:
  crd:
    spec:
      names:
        kind: K8sContainerEphemeralStorageLimit
      validation:
        # Schema for the `parameters` field
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
            ephemeral-storage:
              description: "The maximum allowed ephemeral storage limit on a Pod, exclusive."
              type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8scontainerephemeralstoragelimit

        import data.lib.exclude_update.is_update
        import data.lib.exempt_container.is_exempt

        missing(obj, field) = true {
          not obj[field]
        }

        missing(obj, field) = true {
          obj[field] == ""
        }

        has_field(object, field) = true {
            object[field]
        }

        # 10 ** 21
        storage_multiple("E") = 1000000000000000000000 { true }

        # 10 ** 18
        storage_multiple("P") = 1000000000000000000 { true }

        # 10 ** 15
        storage_multiple("T") = 1000000000000000 { true }

        # 10 ** 12
        storage_multiple("G") = 1000000000000 { true }

        # 10 ** 9
        storage_multiple("M") = 1000000000 { true }

        # 10 ** 6
        storage_multiple("k") = 1000000 { true }

        # 10 ** 3
        storage_multiple("") = 1000 { true }

        # Kubernetes accepts millibyte precision when it probably shouldn't.
        # https://github.com/kubernetes/kubernetes/issues/28741
        # 10 ** 0
        storage_multiple("m") = 1 { true }

        # 1000 * 2 ** 10
        storage_multiple("Ki") = 1024000 { true }

        # 1000 * 2 ** 20
        storage_multiple("Mi") = 1048576000 { true }

        # 1000 * 2 ** 30
        storage_multiple("Gi") = 1073741824000 { true }

        # 1000 * 2 ** 40
        storage_multiple("Ti") = 1099511627776000 { true }

        # 1000 * 2 ** 50
        storage_multiple("Pi") = 1125899906842624000 { true }

        # 1000 * 2 ** 60
        storage_multiple("Ei") = 1152921504606846976000 { true }

        get_suffix(storage) = suffix {
          not is_string(storage)
          suffix := ""
        }

        get_suffix(storage) = suffix {
          is_string(storage)
          count(storage) > 0
          suffix := substring(storage, count(storage) - 1, -1)
          storage_multiple(suffix)
        }

        get_suffix(storage) = suffix {
          is_string(storage)
          count(storage) > 1
          suffix := substring(storage, count(storage) - 2, -1)
          storage_multiple(suffix)
        }

        get_suffix(storage) = suffix {
          is_string(storage)
          count(storage) > 1
          not storage_multiple(substring(storage, count(storage) - 1, -1))
          not storage_multiple(substring(storage, count(storage) - 2, -1))
          suffix := ""
        }

        get_suffix(storage) = suffix {
          is_string(storage)
          count(storage) == 1
          not storage_multiple(substring(storage, count(storage) - 1, -1))
          suffix := ""
        }

        get_suffix(storage) = suffix {
          is_string(storage)
          count(storage) == 0
          suffix := ""
        }

        canonify_storage(orig) = new {
          is_number(orig)
          new := orig * 1000
        }

        canonify_storage(orig) = new {
          not is_number(orig)
          suffix := get_suffix(orig)
          raw := replace(orig, suffix, "")
          regex.match("^[0-9]+(\\.[0-9]+)?$", raw)
          new := to_number(raw) * storage_multiple(suffix)
        }

        violation[{"msg": msg}] {
          # spec.containers.resources.limits["ephemeral-storage"] field is immutable.
          not is_update(input.review)

          general_violation[{"msg": msg, "field": "containers"}]
        }

        violation[{"msg": msg}] {
          not is_update(input.review)
          general_violation[{"msg": msg, "field": "initContainers"}]
        }

        # Ephemeral containers not checked as it is not possible to set field.

        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          not is_exempt(container)
          storage_orig := container.resources.limits["ephemeral-storage"]
          not canonify_storage(storage_orig)
          msg := sprintf("container <%v> ephemeral-storage limit <%v> could not be parsed", [container.name, storage_orig])
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
          missing(container.resources.limits, "ephemeral-storage")
          msg := sprintf("container <%v> has no ephemeral-storage limit", [container.name])
        }

        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          not is_exempt(container)
          storage_orig := container.resources.limits["ephemeral-storage"]
          storage := canonify_storage(storage_orig)
          max_storage_orig := input.parameters["ephemeral-storage"]
          max_storage := canonify_storage(max_storage_orig)
          storage > max_storage
          msg := sprintf("container <%v> ephemeral-storage limit <%v> is higher than the maximum allowed of <%v>", [container.name, storage_orig, max_storage_orig])
        }
      libs:
        - |
          package lib.exclude_update

          is_update(review) {
              review.operation == "UPDATE"
          }
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
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/ephemeralstoragelimit/template.yaml
```
## Examples
<details>
<summary>ephemeral-storage-limit</summary><blockquote>

<details>
<summary>constraint</summary>

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerEphemeralStorageLimit
metadata:
  name: container-ephemeral-storage-limit
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
  parameters:
    ephemeral-storage: "500Mi"

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/ephemeralstoragelimit/samples/container-must-have-ephemeral-storage-limit/constraint.yaml
```

</details>

<details>
<summary>ephemeral-storage-limit-100Mi</summary>

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
          cpu: "100m"
          memory: "1Gi"

          ephemeral-storage: "100Mi"

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/ephemeralstoragelimit/samples/container-must-have-ephemeral-storage-limit/example_allowed_ephemeral-storage.yaml
```

</details>
<details>
<summary>ephemeral-storage-limit-initContainer-100Mi</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: opa-allowed
  labels:
    owner: me.agilebank.demo
spec:
  initContainers:
    - name: init-opa
      image: openpolicyagent/opa:0.9.2
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"
      resources:
        limits:
          cpu: "100m"
          memory: "1Gi"
          ephemeral-storage: "100Mi"


  containers:
    - name: opa
      image: openpolicyagent/opa:0.9.2
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"
      resources:
        limits:
          cpu: "100m"
          memory: "1Gi"
          ephemeral-storage: "100Mi"

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/ephemeralstoragelimit/samples/container-must-have-ephemeral-storage-limit/example_allowed_ephemeral-storage-initContainer.yaml
```

</details>
<details>
<summary>ephemeral-storage-limit-unspecified</summary>

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
          cpu: "100m"
          memory: "2Gi"

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/ephemeralstoragelimit/samples/container-must-have-ephemeral-storage-limit/example_disallowed_ephemeral_storage_limit_unspecified.yaml
```

</details>
<details>
<summary>ephemeral-storage-limit-1Pi</summary>

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
          cpu: "100m"
          memory: "1Gi"

          ephemeral-storage: "1Pi"

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/ephemeralstoragelimit/samples/container-must-have-ephemeral-storage-limit/example_disallowed_ephemeral_storage_limit_1Pi.yaml
```

</details>
<details>
<summary>ephemeral-storage-limit-initContainer-1Pi</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: opa-disallowed
  labels:
    owner: me.agilebank.demo
spec:
  initContainers:
    - name: init-opa
      image: openpolicyagent/opa:0.9.2
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"
      resources:
        limits:
          cpu: "100m"
          memory: "1Gi"
          ephemeral-storage: "1Pi"
  containers:
    - name: opa
      image: openpolicyagent/opa:0.9.2
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"
      resources:
        limits:
          cpu: "100m"
          memory: "1Gi"
          ephemeral-storage: "100Mi"

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/ephemeralstoragelimit/samples/container-must-have-ephemeral-storage-limit/example_disallowed_ephemeral_storage_limit_1Pi-initContainer.yaml
```

</details>


</blockquote></details>