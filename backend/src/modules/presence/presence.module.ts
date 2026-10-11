import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { PresenceController } from './presence.controller';
import { PresenceService }    from './presence.service';
import { User }               from '../users/entities/user.entity';

// Présence « En ligne / Vu à … ». Les règles d'affichage (isOnline) sont
// dans presence.util.ts, partagé par chat, vendors et products.
@Module({
  imports:     [TypeOrmModule.forFeature([User])],
  controllers: [PresenceController],
  providers:   [PresenceService],
  exports:     [PresenceService],
})
export class PresenceModule {}
