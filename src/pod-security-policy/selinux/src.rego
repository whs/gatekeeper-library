package k8spspselinux

import data.lib.exclude_update.is_update
import data.lib.exempt_container.is_exempt

# Disallow top level custom SELinux options
violation[{"msg": msg, "details": {}}] {
    # spec.securityContext.seLinuxOptions field is immutable.
    not is_update(input.review)

    has_field(input.review.object.spec.securityContext, "seLinuxOptions")
    not input_seLinuxOptions_allowed(input.review.object.spec.securityContext.seLinuxOptions)
    msg := sprintf("SELinux options is not allowed, pod: %v. Allowed options: %v", [input.review.object.metadata.name, input.parameters.allowedSELinuxOptions])
}
# Disallow container level custom SELinux options
violation[{"msg": msg, "details": {}}] {
    # spec.containers.securityContext.seLinuxOptions field is immutable.
    not is_update(input.review)

    c := input_security_context[_]
    not is_exempt(c)
    has_field(c.securityContext, "seLinuxOptions")
    not input_seLinuxOptions_allowed(c.securityContext.seLinuxOptions)
    msg := sprintf("SELinux options is not allowed, pod: %v, container %v. Allowed options: %v", [input.review.object.metadata.name, c.name, input.parameters.allowedSELinuxOptions])
}

input_seLinuxOptions_allowed(options) {
    params := input.parameters.allowedSELinuxOptions[_]
    field_allowed("level", options, params)
    field_allowed("role", options, params)
    field_allowed("type", options, params)
    field_allowed("user", options, params)
}

field_allowed(field, options, params) {
    params[field] == options[field]
}
field_allowed(field, options, _) {
    not has_field(options, field)
}

input_security_context[c] {
    c := input.review.object.spec.containers[_]
    has_field(c.securityContext, "seLinuxOptions")
}
input_security_context[c] {
    c := input.review.object.spec.initContainers[_]
    has_field(c.securityContext, "seLinuxOptions")
}
input_security_context[c] {
    c := input.review.object.spec.ephemeralContainers[_]
    has_field(c.securityContext, "seLinuxOptions")
}

# has_field returns whether an object has a field
has_field(object, field) = true {
    object[field]
}
