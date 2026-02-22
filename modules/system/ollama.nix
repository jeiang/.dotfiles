{pkgs, ...}: let
  url = "127.0.0.1:${port_str}";
  http_url = "http://${url}";
  port = 11111;
  port_str = toString port;
in {
  environment = {
    systemPackages = with pkgs; [
      claude-code
    ];
    variables = {
      OLLAMA_HOST = url;
      OLLAMA_API_BASE = http_url;
    };
  };
  services = {
    ollama = {
      inherit port;
      enable = true;
      package = pkgs.ollama-vulkan;
      loadModels = [
        "deepseek-r1:14b"
        "qwen3-coder-next:latest"
        "gemma3:4b"
        "gemma3:27b"
        "glm-4.7-flash:latest"
        "qwen3:8b"
        "ministral-3:8b"
      ];
      environmentVariables = {
        OLLAMA_CONTEXT_LENGTH = "64000";
        GGML_VK_VISIBLE_DEVICES = "0";
      };
    };
    nextjs-ollama-llm-ui = {
      enable = true;
      hostname = "0.0.0.0";
      port = 11110;
      ollamaUrl = http_url;
    };
  };
  networking.firewall.allowedTCPPorts = [11110];
}
