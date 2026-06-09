import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { ChatController } from './chat.controller';
import { ChatService }    from './chat.service';
import { Conversation }   from './entities/conversation.entity';
import { Message }        from './entities/message.entity';
import { VendorProfile }  from '../users/entities/vendor-profile.entity';
import { Product }        from '../products/entities/product.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      Conversation,
      Message,
      VendorProfile,
      Product,
    ]),
  ],
  controllers: [ChatController],
  providers:   [ChatService],
  exports:     [ChatService, TypeOrmModule],
})
export class ChatModule {}