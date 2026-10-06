package ar.edu.utn.frc.tienda.version;

import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class VersionController {

    private final String version;

    public VersionController(@Value("${app.version}") String version) {
        this.version = version;
    }

    @GetMapping("/api/version")
    public Map<String, String> version() {
        return Map.of("name", "tienda-api", "version", version);
    }
}
