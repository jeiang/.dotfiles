{pkgs, ...}: let
  url = "127.0.0.1:${port_str}";
  http_url = "http://${url}";
  port = 11111;
  port_str = builtins.toString port;
in {
  environment.variables = {
    OLLAMA_HOST = url;
    OLLAMA_API_BASE = http_url;
  };
  services = {
    ollama = {
      inherit port;
      enable = true;
      package = pkgs.ollama-vulkan;
      loadModels = [
        "deepseek-r1:14b"
      ];
      environmentVariables = {
        OLLAMA_CONTEXT_LENGTH = "8192";
        GGML_VK_VISIBLE_DEVICES = "0";
      };
    };
    nextjs-ollama-llm-ui = {
      enable = true;
      port = 11110;
      ollamaUrl = http_url;
    };
  };
}
