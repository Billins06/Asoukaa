import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { UsersController } from './users.controller';
import { UsersService }    from './users.service';
import { User }            from './entities/user.entity';
import { UserRole }        from './entities/user-role.entity';
import { Address }         from './entities/address.entity';
import { VendorProfile }   from './entities/vendor-profile.entity';
import { DeliveryAgentProfile } from './entities/delivery-agent-profile.entity';
import { CommonModule }    from '../../common/common.module';
import { UploadModule }    from '../upload/upload.module';
import { EmailChange }     from './email-change/email-change.entity';
import { EmailChangeService } from './email-change/email-change.service';
import {
  EmailChangeController,
  EmailChangeRevertController,
} from './email-change/email-change.controller';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      User,
      UserRole,
      Address,
      VendorProfile,
      DeliveryAgentProfile,
      EmailChange,
    ]),
    CommonModule,
    // UploadService : contrôle de l'URL d'avatar dans updateProfile.
    // UploadModule n'importe pas UsersModule → pas de dépendance circulaire.
    UploadModule,
  ],
  controllers: [UsersController, EmailChangeController, EmailChangeRevertController],
  providers:   [UsersService, EmailChangeService],
  exports:     [UsersService, TypeOrmModule],
})
export class UsersModule {}