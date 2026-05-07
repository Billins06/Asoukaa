import { Module, Global } from '@nestjs/common';
import { MailService } from './mail.service';

// @Global() permet d'injecter MailService dans n'importe quel module
// sans avoir à importer MailModule partout
@Global()
@Module({
  providers: [MailService],
  exports: [MailService],
})
export class MailModule {}