package ar.edu.utn.frc.tienda.version;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class VersionControllerTest {

    @Test
    void exposesConfiguredVersion() {
        VersionController controller = new VersionController("2.3.4");

        assertThat(controller.version()).containsEntry("version", "2.3.4");
    }
}
