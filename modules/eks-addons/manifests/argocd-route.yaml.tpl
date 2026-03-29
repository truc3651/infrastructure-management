apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd-route
  namespace: ${argocd_namespace}
spec:
  parentRefs:
    - name: main-gateway
      namespace: ${gateway_namespace}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /argocd
      backendRefs:
        - name: argocd-server
          namespace: ${argocd_namespace}
          port: 80
      filters:
        - type: URLRewrite
          urlRewrite:
            path:
              type: ReplacePrefixMatch
              replacePrefixMatch: /