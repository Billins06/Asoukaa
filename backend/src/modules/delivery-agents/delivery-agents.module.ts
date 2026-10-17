import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { DeliveryAgentsController } from './delivery-agents.controller';
import { DeliveryAgentsService }    from './delivery-agents.service';
import { DeliveryAgentProfile }     from '../users/entities/delivery-agent-profile.entity';
import { UserRole }                 from '../users/entities/user-role.entity';
import { User }                     from '../users/entities/user.entity';
import { DeliveryEarning }          from '../delivery/entities/delivery-earning.entity';
import { CommonModule }             from '../../common/common.module';
import { UploadModule }             from '../upload/upload.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      DeliveryAgentProfile,
      UserRole,
      User,
      DeliveryEarning,
    ]),
    CommonModule,
    // UploadService : rafraîchit les URL signées des documents (fiches admin)
    UploadModule,
  ],
  controllers: [DeliveryAgentsController],
  providers:   [DeliveryAgentsService],
  exports:     [DeliveryAgentsService, TypeOrmModule],
})
export class DeliveryAgentsModule {}