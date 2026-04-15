abstract class SubInferenceService {
  Future<String> infer(String instruction, String input);
}

// NOTE: In the main isolate, this would be implemented via GemmaController.
// In a sub-isolate, this would send an IPC message to the main isolate to perform inference.
